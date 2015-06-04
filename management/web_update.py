# Creates an nginx configuration file so we serve HTTP/HTTPS on all
# domains for which a mail account has been set up.
########################################################################

import os, os.path, shutil, re, tempfile, rtyaml

from mailconfig import get_mail_domains
from dns_update import get_custom_dns_config, do_dns_update, get_dns_zones
from utils import shell, safe_domain_name, sort_domains

def get_web_domains(env):
	# What domains should we serve websites for?
	domains = set()

	# At the least it's the PRIMARY_HOSTNAME so we can serve webmail
	# as well as Z-Push for Exchange ActiveSync.
	domains.add(env['PRIMARY_HOSTNAME'])

	# Also serve web for all mail domains so that we might at least
	# provide auto-discover of email settings, and also a static website
	# if the user wants to make one. These will require an SSL cert.
	# ...Unless the domain has an A/AAAA record that maps it to a different
	# IP address than this box. Remove those domains from our list.
	domains |= (get_mail_domains(env) - get_domains_with_a_records(env))

	# Sort the list so the nginx conf gets written in a stable order.
	domains = sort_domains(domains, env)

	return domains

def get_domains_with_a_records(env):
	domains = set()
	dns = get_custom_dns_config(env)
	for domain, rtype, value in dns:
		if rtype == "CNAME" or (rtype in ("A", "AAAA") and value != "local"):
			domains.add(domain)
	return domains

def get_default_www_redirects(env):
	# Returns a list of www subdomains that we want to provide default redirects
	# for, i.e. any www's that aren't domains the user has actually configured
	# to serve for real. Which would be unusual.
	web_domains = set(get_web_domains(env))
	www_domains = set('www.' + zone for zone, zonefile in get_dns_zones(env))
	return sort_domains(www_domains - web_domains - get_domains_with_a_records(env), env)

def do_web_update(env):
	# Build an nginx configuration file.
	nginx_conf = open(os.path.join(os.path.dirname(__file__), "../conf/nginx-top.conf")).read()

	# Load the templates.
	template0 = open(os.path.join(os.path.dirname(__file__), "../conf/nginx.conf")).read()
	template1 = open(os.path.join(os.path.dirname(__file__), "../conf/nginx-alldomains.conf")).read()
	template2 = open(os.path.join(os.path.dirname(__file__), "../conf/nginx-primaryonly.conf")).read()
	template3 = "\trewrite / https://$REDIRECT_DOMAIN permanent;\n"

	# Add the PRIMARY_HOST configuration first so it becomes nginx's default server.
	nginx_conf += make_domain_config(env['PRIMARY_HOSTNAME'], [template0, template1, template2], env)

	# Add configuration all other web domains.
	for domain in get_web_domains(env):
		if domain == env['PRIMARY_HOSTNAME']: continue # handled above
		nginx_conf += make_domain_config(domain, [template0, template1], env)

	# Add default www redirects.
	for domain in get_default_www_redirects(env):
		nginx_conf += make_domain_config(domain, [template0, template3], env)

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

def make_domain_config(domain, templates, env):
	# GET SOME VARIABLES

	# Where will its root directory be for static files?
	root = get_web_root(domain, env)

	# What private key and SSL certificate will we use for this domain?
	ssl_key, ssl_certificate, ssl_via = get_domain_ssl_files(domain, env)

	# For hostnames created after the initial setup, ensure we have an SSL certificate
	# available. Make a self-signed one now if one doesn't exist.
	ensure_ssl_certificate_exists(domain, ssl_key, ssl_certificate, env)

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
	nginx_conf_extra += "# ssl files sha1: %s / %s\n" % (hashfile(ssl_key), hashfile(ssl_certificate))

	# Add in any user customizations in YAML format.
	nginx_conf_custom_fn = os.path.join(env["STORAGE_ROOT"], "www/custom.yaml")
	if os.path.exists(nginx_conf_custom_fn):
		yaml = rtyaml.load(open(nginx_conf_custom_fn))
		if domain in yaml:
			yaml = yaml[domain]
			for path, url in yaml.get("proxies", {}).items():
				nginx_conf_extra += "\tlocation %s {\n\t\tproxy_pass %s;\n\t}\n" % (path, url)
			for path, url in yaml.get("redirects", {}).items():
				nginx_conf_extra += "\trewrite %s %s permanent;\n" % (path, url)

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
	nginx_conf = nginx_conf.replace("$SSL_KEY", ssl_key)
	nginx_conf = nginx_conf.replace("$SSL_CERTIFICATE", ssl_certificate)
	nginx_conf = nginx_conf.replace("$REDIRECT_DOMAIN", re.sub(r"^www\.", "", domain)) # for default www redirects to parent domain

	return nginx_conf

def get_web_root(domain, env, test_exists=True):
	# Try STORAGE_ROOT/web/domain_name if it exists, but fall back to STORAGE_ROOT/web/default.
	for test_domain in (domain, 'default'):
		root = os.path.join(env["STORAGE_ROOT"], "www", safe_domain_name(test_domain))
		if os.path.exists(root) or not test_exists: break
	return root

def get_domain_ssl_files(domain, env, allow_shared_cert=True):
	# What SSL private key will we use? Allow the user to override this, but
	# in many cases using the same private key for all domains would be fine.
	# Don't allow the user to override the key for PRIMARY_HOSTNAME because
	# that's what's in the main file.
	ssl_key = os.path.join(env["STORAGE_ROOT"], 'ssl/ssl_private_key.pem')
	ssl_key_is_alt = False
	alt_key = os.path.join(env["STORAGE_ROOT"], 'ssl/%s/private_key.pem' % safe_domain_name(domain))
	if domain != env['PRIMARY_HOSTNAME'] and os.path.exists(alt_key):
		ssl_key = alt_key
		ssl_key_is_alt = True

	# What SSL certificate will we use?
	ssl_certificate_primary = os.path.join(env["STORAGE_ROOT"], 'ssl/ssl_certificate.pem')
	ssl_via = None
	if domain == env['PRIMARY_HOSTNAME']:
		# For PRIMARY_HOSTNAME, use the one we generated at set-up time.
		ssl_certificate = ssl_certificate_primary
	else:
		# For other domains, we'll probably use a certificate in a different path.
		ssl_certificate = os.path.join(env["STORAGE_ROOT"], 'ssl/%s/ssl_certificate.pem' % safe_domain_name(domain))

		# But we can be smart and reuse the main SSL certificate if is has
		# a Subject Alternative Name matching this domain. Don't do this if
		# the user has uploaded a different private key for this domain.
		if not ssl_key_is_alt and allow_shared_cert:
			from status_checks import check_certificate
			if check_certificate(domain, ssl_certificate_primary, None)[0] == "OK":
				ssl_certificate = ssl_certificate_primary
				ssl_via = "Using multi/wildcard certificate of %s." % env['PRIMARY_HOSTNAME']

			# For a 'www.' domain, see if we can reuse the cert of the parent.
			elif domain.startswith('www.'):
				ssl_certificate_parent = os.path.join(env["STORAGE_ROOT"], 'ssl/%s/ssl_certificate.pem' % safe_domain_name(domain[4:]))
				if os.path.exists(ssl_certificate_parent) and check_certificate(domain, ssl_certificate_parent, None)[0] == "OK":
					ssl_certificate = ssl_certificate_parent
					ssl_via = "Using multi/wildcard certificate of %s." % domain[4:]

	return ssl_key, ssl_certificate, ssl_via

def ensure_ssl_certificate_exists(domain, ssl_key, ssl_certificate, env):
	# For domains besides PRIMARY_HOSTNAME, generate a self-signed certificate if
	# a certificate doesn't already exist. See setup/mail.sh for documentation.

	if domain == env['PRIMARY_HOSTNAME']:
		return

	# Sanity check. Shouldn't happen. A non-primary domain might use this
	# certificate (see above), but then the certificate should exist anyway.
	if ssl_certificate == os.path.join(env["STORAGE_ROOT"], 'ssl/ssl_certificate.pem'):
		return

	if os.path.exists(ssl_certificate):
		return

	os.makedirs(os.path.dirname(ssl_certificate), exist_ok=True)

	# Generate a new self-signed certificate using the same private key that we already have.

	# Start with a CSR written to a temporary file.
	with tempfile.NamedTemporaryFile(mode="w") as csr_fp:
		csr_fp.write(create_csr(domain, ssl_key, env))
		csr_fp.flush() # since we won't close until after running 'openssl x509', since close triggers delete.

		# And then make the certificate.
		shell("check_call", [
			"openssl", "x509", "-req",
			"-days", "365",
			"-in", csr_fp.name,
			"-signkey", ssl_key,
			"-out", ssl_certificate])

def create_csr(domain, ssl_key, env):
	return shell("check_output", [
                "openssl", "req", "-new",
                "-key", ssl_key,
                "-sha256",
                "-subj", "/C=%s/ST=/L=/O=/CN=%s" % (env["CSR_COUNTRY"], domain)])

def install_cert(domain, ssl_cert, ssl_chain, env):
	if domain not in get_web_domains(env):
		return "Invalid domain name."

	# Write the combined cert+chain to a temporary path and validate that it is OK.
	# The certificate always goes above the chain.
	import tempfile, os
	fd, fn = tempfile.mkstemp('.pem')
	os.write(fd, (ssl_cert + '\n' + ssl_chain).encode("ascii"))
	os.close(fd)

	# Do validation on the certificate before installing it.
	from status_checks import check_certificate
	ssl_key, ssl_certificate, ssl_via = get_domain_ssl_files(domain, env, allow_shared_cert=False)
	cert_status, cert_status_details = check_certificate(domain, fn, ssl_key)
	if cert_status != "OK":
		if cert_status == "SELF-SIGNED":
			cert_status = "This is a self-signed certificate. I can't install that."
		os.unlink(fn)
		if cert_status_details is not None:
			cert_status += " " + cert_status_details
		return cert_status

	# Copy the certificate to its expected location.
	os.makedirs(os.path.dirname(ssl_certificate), exist_ok=True)
	shutil.move(fn, ssl_certificate)

	ret = ["OK"]

	# When updating the cert for PRIMARY_HOSTNAME, also update DNS because it is
	# used in the DANE TLSA record and restart postfix and dovecot which use
	# that certificate.
	if domain == env['PRIMARY_HOSTNAME']:
		ret.append( do_dns_update(env) )

		shell('check_call', ["/usr/sbin/service", "postfix", "restart"])
		shell('check_call', ["/usr/sbin/service", "dovecot", "restart"])
		ret.append("mail services restarted")

	# Kick nginx so it sees the cert.
	ret.append( do_web_update(env) )
	return "\n".join(ret)

def get_web_domains_info(env):
	# load custom settings so we can tell what domains have a redirect or proxy set up on '/',
	# which means static hosting is not happening
	custom_settings = { }
	nginx_conf_custom_fn = os.path.join(env["STORAGE_ROOT"], "www/custom.yaml")
	if os.path.exists(nginx_conf_custom_fn):
		custom_settings = rtyaml.load(open(nginx_conf_custom_fn))
	def has_root_proxy_or_redirect(domain):
		return custom_settings.get(domain, {}).get('redirects', {}).get('/') or custom_settings.get(domain, {}).get('proxies', {}).get('/')

	# for the SSL config panel, get cert status
	def check_cert(domain):
		from status_checks import check_certificate
		ssl_key, ssl_certificate, ssl_via = get_domain_ssl_files(domain, env)
		if not os.path.exists(ssl_certificate):
			return ("danger", "No Certificate Installed")
		cert_status, cert_status_details = check_certificate(domain, ssl_certificate, ssl_key)
		if cert_status == "OK":
			if not ssl_via:
				return ("success", "Signed & valid. " + cert_status_details)
			else:
				# This is an alternate domain but using the same cert as the primary domain.
				return ("success", "Signed & valid. " + ssl_via)
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
			"static_enabled": not has_root_proxy_or_redirect(domain),
		}
		for domain in get_web_domains(env)
	] + \
	[
		{
			"domain": domain,
			"ssl_certificate": check_cert(domain),
			"static_enabled": False,
		}
		for domain in get_default_www_redirects(env)
	]
