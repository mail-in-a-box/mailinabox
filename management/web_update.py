# Creates an nginx configuration file so we serve HTTP/HTTPS on all
# domains for which a mail account has been set up.
########################################################################

import os.path, re, rtyaml

from mailconfig import get_mail_domains
from dns_update import get_custom_dns_config, get_dns_zones
from ssl_certificates import get_ssl_certificates, get_domain_ssl_files, check_certificate
from utils import shell, safe_domain_name, sort_domains

def get_web_domains(env, include_www_redirects=True, exclude_dns_elsewhere=True):
	# What domains should we serve HTTP(S) for?
	domains = set()

	# Serve web for all mail domains so that we might at least
	# provide auto-discover of email settings, and also a static website
	# if the user wants to make one.
	domains |= get_mail_domains(env)

	if include_www_redirects:
		# Add 'www.' subdomains that we want to provide default redirects
		# to the main domain for. We'll add 'www.' to any DNS zones, i.e.
		# the topmost of each domain we serve.
		domains |= set('www.' + zone for zone, zonefile in get_dns_zones(env))

	# Add Autoconfiguration domains for domains that there are user accounts at:
	# 'autoconfig.' for Mozilla Thunderbird auto setup.
	# 'autodiscover.' for Activesync autodiscovery.
	domains |= set('autoconfig.' + maildomain for maildomain in get_mail_domains(env, users_only=True))
	domains |= set('autodiscover.' + maildomain for maildomain in get_mail_domains(env, users_only=True))

	# 'mta-sts.' for MTA-STS support for all domains that have email addresses.
	domains |= set('mta-sts.' + maildomain for maildomain in get_mail_domains(env))

	if exclude_dns_elsewhere:
		# ...Unless the domain has an A/AAAA record that maps it to a different
		# IP address than this box. Remove those domains from our list.
		domains -= get_domains_with_a_records(env)

	# Ensure the PRIMARY_HOSTNAME is in the list so we can serve webmail
	# as well as Z-Push for Exchange ActiveSync. This can't be removed
	# by a custom A/AAAA record and is never a 'www.' redirect.
	domains.add(env['PRIMARY_HOSTNAME'])

	# Sort the list so the nginx conf gets written in a stable order.
	domains = sort_domains(domains, env)

	return domains

def get_domains_with_a_records(env):
	domains = set()
	dns = get_custom_dns_config(env)
	for domain, rtype, value in dns:
		if rtype == "CNAME" or (rtype in ("A", "AAAA") and value not in ("local", env['PUBLIC_IP'])):
			domains.add(domain)
	return domains

def get_web_domains_with_root_overrides(env):
	# Load custom settings so we can tell what domains have a redirect or proxy set up on '/',
	# which means static hosting is not happening.
	root_overrides = { }
	nginx_conf_custom_fn = os.path.join(env["STORAGE_ROOT"], "www/custom.yaml")
	if os.path.exists(nginx_conf_custom_fn):
		custom_settings = rtyaml.load(open(nginx_conf_custom_fn))
		for domain, settings in custom_settings.items():
			for type, value in [('redirect', settings.get('redirects', {}).get('/')),
				('proxy', settings.get('proxies', {}).get('/'))]:
				if value:
					root_overrides[domain] = (type, value)
	return root_overrides

def do_web_update(env):
	# Pre-load what SSL certificates we will use for each domain.
	ssl_certificates = get_ssl_certificates(env)

	# Build an nginx configuration file.
	nginx_conf = open(os.path.join(os.path.dirname(__file__), "../conf/nginx-top.conf")).read()

	# Load the templates.
	template0 = open(os.path.join(os.path.dirname(__file__), "../conf/nginx.conf")).read()
	template1 = open(os.path.join(os.path.dirname(__file__), "../conf/nginx-alldomains.conf")).read()
	template2 = open(os.path.join(os.path.dirname(__file__), "../conf/nginx-primaryonly.conf")).read()
	template3 = "\trewrite ^(.*) https://$REDIRECT_DOMAIN$1 permanent;\n"

	# Add the PRIMARY_HOST configuration first so it becomes nginx's default server.
	nginx_conf += make_domain_config(env['PRIMARY_HOSTNAME'], [template0, template1, template2], ssl_certificates, env)

	# Add configuration all other web domains.
	has_root_proxy_or_redirect = get_web_domains_with_root_overrides(env)
	web_domains_not_redirect = get_web_domains(env, include_www_redirects=False)
	for domain in get_web_domains(env):
		if domain == env['PRIMARY_HOSTNAME']:
			# PRIMARY_HOSTNAME is handled above.
			continue
		if domain in web_domains_not_redirect:
			# This is a regular domain.
			if domain not in has_root_proxy_or_redirect:
				nginx_conf += make_domain_config(domain, [template0, template1], ssl_certificates, env)
			else:
				nginx_conf += make_domain_config(domain, [template0], ssl_certificates, env)
		else:
			# Add default 'www.' redirect.
			nginx_conf += make_domain_config(domain, [template0, template3], ssl_certificates, env)

	# Did the file change? If not, don't bother writing & restarting nginx.
	nginx_conf_fn = "/etc/nginx/conf.d/local.conf"
	if os.path.exists(nginx_conf_fn):
		with open(nginx_conf_fn) as f:
			if f.read() == nginx_conf:
				return ""

	# Save the file.
	with open(nginx_conf_fn, "w") as f:
		f.write(nginx_conf)

	# Kick nginx. Since this might be called from the web admin
	# don't do a 'restart'. That would kill the connection before
	# the API returns its response. A 'reload' should be good
	# enough and doesn't break any open connections.
	shell('check_call', ["/usr/sbin/service", "nginx", "reload"])

	return "web updated\n"

def make_domain_config(domain, templates, ssl_certificates, env):
	# GET SOME VARIABLES

	# Where will its root directory be for static files?
	root = get_web_root(domain, env)

	# What private key and SSL certificate will we use for this domain?
	tls_cert = get_domain_ssl_files(domain, ssl_certificates, env)

	# ADDITIONAL DIRECTIVES.

	nginx_conf_extra = ""

	# Because the certificate may change, we should recognize this so we
	# can trigger an nginx update.
	def hashfile(filepath):
		import hashlib
		sha1 = hashlib.sha1()
		f = open(filepath, 'rb')
		try:
			sha1.update(f.read())
		finally:
			f.close()
		return sha1.hexdigest()
	nginx_conf_extra += "# ssl files sha1: %s / %s\n" % (hashfile(tls_cert["private-key"]), hashfile(tls_cert["certificate"]))

	# Add in any user customizations in YAML format.
	hsts = "yes"
	nginx_conf_custom_fn = os.path.join(env["STORAGE_ROOT"], "www/custom.yaml")
	if os.path.exists(nginx_conf_custom_fn):
		yaml = rtyaml.load(open(nginx_conf_custom_fn))
		if domain in yaml:
			yaml = yaml[domain]

			# any proxy or redirect here?
			for path, url in yaml.get("proxies", {}).items():
				nginx_conf_extra += "\tlocation %s {" % path
				nginx_conf_extra += "\n\t\tproxy_pass %s;" % url
				nginx_conf_extra += "\n\t\tproxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;"
				nginx_conf_extra += "\n\t}\n"
			for path, alias in yaml.get("aliases", {}).items():
				nginx_conf_extra += "\tlocation %s {" % path
				nginx_conf_extra += "\n\t\talias %s;" % alias
				nginx_conf_extra += "\n\t}\n"
			for path, url in yaml.get("redirects", {}).items():
				nginx_conf_extra += "\trewrite %s %s permanent;\n" % (path, url)

			# override the HSTS directive type
			hsts = yaml.get("hsts", hsts)

	# Add the HSTS header.
	if hsts == "yes":
		nginx_conf_extra += "add_header Strict-Transport-Security max-age=15768000;\n"
	elif hsts == "preload":
		nginx_conf_extra += "add_header Strict-Transport-Security \"max-age=15768000; includeSubDomains; preload\";\n"

	# Add in any user customizations in the includes/ folder.
	nginx_conf_custom_include = os.path.join(env["STORAGE_ROOT"], "www", safe_domain_name(domain) + ".conf")
	if os.path.exists(nginx_conf_custom_include):
		nginx_conf_extra += "\tinclude %s;\n" % (nginx_conf_custom_include)
	# PUT IT ALL TOGETHER

	# Combine the pieces. Iteratively place each template into the "# ADDITIONAL DIRECTIVES HERE" placeholder
	# of the previous template.
	nginx_conf = "# ADDITIONAL DIRECTIVES HERE\n"
	for t in templates + [nginx_conf_extra]:
		nginx_conf = re.sub("[ \t]*# ADDITIONAL DIRECTIVES HERE *\n", t, nginx_conf)

	# Replace substitution strings in the template & return.
	nginx_conf = nginx_conf.replace("$STORAGE_ROOT", env['STORAGE_ROOT'])
	nginx_conf = nginx_conf.replace("$HOSTNAME", domain)
	nginx_conf = nginx_conf.replace("$ROOT", root)
	nginx_conf = nginx_conf.replace("$SSL_KEY", tls_cert["private-key"])
	nginx_conf = nginx_conf.replace("$SSL_CERTIFICATE", tls_cert["certificate"])
	nginx_conf = nginx_conf.replace("$REDIRECT_DOMAIN", re.sub(r"^www\.", "", domain)) # for default www redirects to parent domain

	return nginx_conf

def get_web_root(domain, env, test_exists=True):
	# Try STORAGE_ROOT/web/domain_name if it exists, but fall back to STORAGE_ROOT/web/default.
	for test_domain in (domain, 'default'):
		root = os.path.join(env["STORAGE_ROOT"], "www", safe_domain_name(test_domain))
		if os.path.exists(root) or not test_exists: break
	return root

def get_web_domains_info(env):
	www_redirects = set(get_web_domains(env)) - set(get_web_domains(env, include_www_redirects=False))
	has_root_proxy_or_redirect = set(get_web_domains_with_root_overrides(env))
	ssl_certificates = get_ssl_certificates(env)

	# for the SSL config panel, get cert status
	def check_cert(domain):
		try:
			tls_cert = get_domain_ssl_files(domain, ssl_certificates, env, allow_missing_cert=True)
		except OSError: # PRIMARY_HOSTNAME cert is missing
			tls_cert = None
		if tls_cert is None: return ("danger", "No certificate installed.")
		cert_status, cert_status_details = check_certificate(domain, tls_cert["certificate"], tls_cert["private-key"])
		if cert_status == "OK":
			return ("success", "Signed & valid. " + cert_status_details)
		elif cert_status == "SELF-SIGNED":
			return ("warning", "Self-signed. Get a signed certificate to stop warnings.")
		else:
			return ("danger", "Certificate has a problem: " + cert_status)

	return [
		{
			"domain": domain,
			"root": get_web_root(domain, env),
			"custom_root": get_web_root(domain, env, test_exists=False),
			"ssl_certificate": check_cert(domain),
			"static_enabled": domain not in (www_redirects | has_root_proxy_or_redirect),
		}
		for domain in get_web_domains(env)
	]
