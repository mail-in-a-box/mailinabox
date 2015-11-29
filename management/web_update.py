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


def get_default_www_redirects(env):
	# Returns a list of www subdomains that we want to provide default redirects
	# for, i.e. any www's that aren't domains the user has actually configured
	# to serve for real. Which would be unusual.
	web_domains = set(get_web_domains(env))
	www_domains = set('www.' + zone for zone, zonefile in get_dns_zones(env))
	return sort_domains(www_domains - web_domains - get_domains_with_a_records(env), env)

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
	for domain in get_web_domains(env):
		if domain == env['PRIMARY_HOSTNAME']: continue # handled above
		if domain not in has_root_proxy_or_redirect:
			nginx_conf += make_domain_config(domain, [template0, template1], ssl_certificates, env)
		else:
			nginx_conf += make_domain_config(domain, [template0], ssl_certificates, env)

	# Add default www redirects.
	for domain in get_default_www_redirects(env):
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
	ssl_key, ssl_certificate, ssl_via = get_domain_ssl_files(domain, ssl_certificates, env)

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
	hsts = "yes"
	nginx_conf_custom_fn = os.path.join(env["STORAGE_ROOT"], "www/custom.yaml")
	if os.path.exists(nginx_conf_custom_fn):
		yaml = rtyaml.load(open(nginx_conf_custom_fn))
		if domain in yaml:
			yaml = yaml[domain]

			# any proxy or redirect here?
			for path, url in yaml.get("proxies", {}).items():
				nginx_conf_extra += "\tlocation %s {\n\t\tproxy_pass %s;\n\t}\n" % (path, url)
			for path, url in yaml.get("redirects", {}).items():
				nginx_conf_extra += "\trewrite %s %s permanent;\n" % (path, url)

			# override the HSTS directive type
			hsts = yaml.get("hsts", hsts)

	# Add the HSTS header.
	if hsts == "yes":
		nginx_conf_extra += "add_header Strict-Transport-Security max-age=31536000;\n"
	elif hsts == "preload":
		nginx_conf_extra += "add_header Strict-Transport-Security \"max-age=10886400; includeSubDomains; preload\";\n"

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

def get_ssl_certificates(env):
	# Scan all of the installed SSL certificates and map every domain
	# that the certificates are good for to the best certificate for
	# the domain.

	from cryptography.hazmat.primitives.asymmetric.rsa import RSAPrivateKey
	from cryptography.x509 import Certificate

	# The certificates are all stored here:
	ssl_root = os.path.join(env["STORAGE_ROOT"], 'ssl')

	# List all of the files in the SSL directory and one level deep.
	def get_file_list():
		for fn in os.listdir(ssl_root):
			fn = os.path.join(ssl_root, fn)
			if os.path.isfile(fn):
				yield fn
			elif os.path.isdir(fn):
				for fn1 in os.listdir(fn):
					fn1 = os.path.join(fn, fn1)
					if os.path.isfile(fn1):
						yield fn1

	# Remember stuff.
	private_keys = { }
	certificates = [ ]

	# Scan each of the files to find private keys and certificates.
	# We must load all of the private keys first before processing
	# certificates so that we can check that we have a private key
	# available before using a certificate.
	from status_checks import load_cert_chain, load_pem
	for fn in get_file_list():
		try:
			pem = load_pem(load_cert_chain(fn)[0])
		except ValueError:
			# Not a valid PEM format for a PEM type we care about.
			continue

		# Remember where we got this object.
		pem._filename = fn

		# Is it a private key?
		if isinstance(pem, RSAPrivateKey):
			private_keys[pem.public_key().public_numbers()] = pem

		# Is it a certificate?
		if isinstance(pem, Certificate):
			certificates.append(pem)

	# Process the certificates.
	domains = { }
	from status_checks import get_certificate_domains
	for cert in certificates:
		# What domains is this certificate good for?
		cert_domains, primary_domain = get_certificate_domains(cert)
		cert._primary_domain = primary_domain

		# Is there a private key file for this certificate?
		private_key = private_keys.get(cert.public_key().public_numbers())
		if not private_key:
			continue
		cert._private_key = private_key

		# Add this cert to the list of certs usable for the domains.
		for domain in cert_domains:
			domains.setdefault(domain, []).append(cert)

	# Sort the certificates to prefer good ones.
	import datetime
	now = datetime.datetime.utcnow()
	ret = { }
	for domain, cert_list in domains.items():
		cert_list.sort(key = lambda cert : (
			# must be valid NOW
			cert.not_valid_before <= now <= cert.not_valid_after,

			# prefer one that is not self-signed
			cert.issuer != cert.subject,

			# prefer one with the expiration furthest into the future so
			# that we can easily rotate to new certs as we get them
			cert.not_valid_after,

			# in case a certificate is installed in multiple paths,
			# prefer the... lexicographically last one?
			cert._filename,

		), reverse=True)
		cert = cert_list.pop(0)
		ret[domain] = {
			"private-key": cert._private_key._filename,
			"certificate": cert._filename,
			"primary-domain": cert._primary_domain,
			}

	return ret

def get_domain_ssl_files(domain, ssl_certificates, env, allow_missing_cert=False):
	# Get the default paths.
	ssl_private_key = os.path.join(os.path.join(env["STORAGE_ROOT"], 'ssl', 'ssl_private_key.pem'))
	ssl_certificate = os.path.join(os.path.join(env["STORAGE_ROOT"], 'ssl', 'ssl_certificate.pem'))

	if domain == env['PRIMARY_HOSTNAME']:
		# The primary domain must use the server certificate because
		# it is hard-coded in some service configuration files.
		return ssl_private_key, ssl_certificate, None

	wildcard_domain = re.sub("^[^\.]+", "*", domain)

	if domain in ssl_certificates:
		cert_info = ssl_certificates[domain]
		cert_type = "multi-domain"
	elif wildcard_domain in ssl_certificates:
		cert_info = ssl_certificates[wildcard_domain]
		cert_type = "wildcard"
	elif not allow_missing_cert:
		# No certificate is available for this domain! Return default files.
		ssl_via = "Using certificate for %s." % env['PRIMARY_HOSTNAME']
		return ssl_private_key, ssl_certificate, ssl_via
	else:
		# No certificate is available - and warn appropriately.
		return None

	# 'via' is a hint to the user about which certificate is in use for the domain
	if cert_info['certificate'] == os.path.join(env["STORAGE_ROOT"], 'ssl', 'ssl_certificate.pem'):
		# Using the server certificate.
		via = "Using same %s certificate as for %s." % (cert_type, env['PRIMARY_HOSTNAME'])
	elif cert_info['primary-domain'] != domain and cert_info['primary-domain'] in ssl_certificates and cert_info == ssl_certificates[cert_info['primary-domain']]:
		via = "Using same %s certificate as for %s." % (cert_type, cert_info['primary-domain'])
	else:
		via = None # don't show a hint - show expiration info instead

	return cert_info['private-key'], cert_info['certificate'], via

def create_csr(domain, ssl_key, env):
	return shell("check_output", [
                "openssl", "req", "-new",
                "-key", ssl_key,
                "-sha256",
                "-subj", "/C=%s/ST=/L=/O=/CN=%s" % (env["CSR_COUNTRY"], domain)])

def install_cert(domain, ssl_cert, ssl_chain, env):
	if domain not in get_web_domains(env) + get_default_www_redirects(env):
		return "Invalid domain name."

	# Write the combined cert+chain to a temporary path and validate that it is OK.
	# The certificate always goes above the chain.
	import tempfile, os
	fd, fn = tempfile.mkstemp('.pem')
	os.write(fd, (ssl_cert + '\n' + ssl_chain).encode("ascii"))
	os.close(fd)

	# Do validation on the certificate before installing it.
	from status_checks import check_certificate
	ssl_private_key = os.path.join(os.path.join(env["STORAGE_ROOT"], 'ssl', 'ssl_private_key.pem'))
	cert_status, cert_status_details = check_certificate(domain, fn, ssl_private_key)
	if cert_status != "OK":
		if cert_status == "SELF-SIGNED":
			cert_status = "This is a self-signed certificate. I can't install that."
		os.unlink(fn)
		if cert_status_details is not None:
			cert_status += " " + cert_status_details
		return cert_status

	# Where to put it?
	# Make a unique path for the certificate.
	from status_checks import load_cert_chain, load_pem, get_certificate_domains
	from cryptography.hazmat.primitives import hashes
	from binascii import hexlify
	cert = load_pem(load_cert_chain(fn)[0])
	all_domains, cn = get_certificate_domains(cert)
	path = "%s-%s-%s.pem" % (
		cn, # common name
		cert.not_valid_after.date().isoformat().replace("-", ""), # expiration date
		hexlify(cert.fingerprint(hashes.SHA256())).decode("ascii")[0:8], # fingerprint prefix
		)
	ssl_certificate = os.path.join(os.path.join(env["STORAGE_ROOT"], 'ssl', path))

	# Install the certificate.
	os.makedirs(os.path.dirname(ssl_certificate), exist_ok=True)
	shutil.move(fn, ssl_certificate)

	ret = ["OK"]

	# When updating the cert for PRIMARY_HOSTNAME, symlink it from the system
	# certificate path, which is hard-coded for various purposes, and then
	# update DNS (because of the DANE TLSA record), postfix, and dovecot,
	# which all use the file.
	if domain == env['PRIMARY_HOSTNAME']:
		# Update symlink.
		system_ssl_certificate = os.path.join(os.path.join(env["STORAGE_ROOT"], 'ssl', 'ssl_certificate.pem'))
		os.unlink(system_ssl_certificate)
		os.symlink(ssl_certificate, system_ssl_certificate)

		# Update DNS & restart postfix and dovecot so they pick up the new file.
		ret.append( do_dns_update(env) )
		shell('check_call', ["/usr/sbin/service", "postfix", "restart"])
		shell('check_call', ["/usr/sbin/service", "dovecot", "restart"])
		ret.append("mail services restarted")

	# Update the web configuration so nginx picks up the new certificate file.
	ret.append( do_web_update(env) )
	return "\n".join(ret)

def get_web_domains_info(env):
	has_root_proxy_or_redirect = get_web_domains_with_root_overrides(env)

	# for the SSL config panel, get cert status
	def check_cert(domain):
		from status_checks import check_certificate
		ssl_certificates = get_ssl_certificates(env)
		x = get_domain_ssl_files(domain, ssl_certificates, env, allow_missing_cert=True)
		if x is None: return ("danger", "No Certificate Installed")
		ssl_key, ssl_certificate, ssl_via = x
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
			"static_enabled": domain not in has_root_proxy_or_redirect,
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
