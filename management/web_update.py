# Creates an nginx configuration file so we serve HTTP/HTTPS on all
# domains for which a mail account has been set up.
########################################################################

import os, os.path

from mailconfig import get_mail_domains
from utils import shell, safe_domain_name

def get_web_domains(env):
	# What domains should we serve HTTP/HTTPS for?
	domains = set()

	# Add all domain names in use by email users and mail aliases.
	domains |= get_mail_domains(env)

	# Ensure the PUBLIC_HOSTNAME is in the list.
	domains.add(env['PUBLIC_HOSTNAME'])

	# Sort the list. Put PUBLIC_HOSTNAME first so it becomes the
	# default server (nginx's default_server).
	domains = sorted(domains, key = lambda domain : (domain != env["PUBLIC_HOSTNAME"], list(reversed(domain.split(".")))) )

	return domains
	

def do_web_update(env):
	# Build an nginx configuration file.
	nginx_conf = ""
	template = open(os.path.join(os.path.dirname(__file__), "../conf/nginx.conf")).read()
	for domain in get_web_domains(env):
		nginx_conf += make_domain_config(domain, template, env)

	# Save the file.
	with open("/etc/nginx/conf.d/local.conf", "w") as f:
		f.write(nginx_conf)

	# Nick nginx.
	shell('check_call', ["/usr/sbin/service", "nginx", "restart"])

	return "OK"

def make_domain_config(domain, template, env):
	# How will we configure this domain.

	# Where will its root directory be for static files? Try STORAGE_ROOT/web/domain_name
	# if it exists, but fall back to STORAGE_ROOT/web/default.
	for test_domain in (domain, 'default'):
		root = os.path.join(env["STORAGE_ROOT"], "www", safe_domain_name(test_domain))
		if os.path.exists(root): break

	# What SSL private key will we use? Allow the user to override this, but
	# in many cases using the same private key for all domains would be fine.
	# Don't allow the user to override the key for PUBLIC_HOSTNAME because
	# that's what's in the main file.
	ssl_key = os.path.join(env["STORAGE_ROOT"], 'ssl/ssl_private_key.pem')
	alt_key = os.path.join(env["STORAGE_ROOT"], 'ssl/domains/%s_private_key.pem' % safe_domain_name(domain))
	if domain != env['PUBLIC_HOSTNAME'] and os.path.exists(alt_key):
		ssl_key = alt_key

	# What SSL certificate will we use? This has to be differnet for each
	# domain name. The certificate is already generated for PUBLIC_HOSTNAME.
	# For other domains, generate a self-signed certificate if one doesn't
	# already exist. See setup/mail.sh for documentation.
	if domain == env['PUBLIC_HOSTNAME']:
		ssl_certificate = os.path.join(env["STORAGE_ROOT"], 'ssl/ssl_certificate.pem')
	else:
		ssl_certificate = os.path.join(env["STORAGE_ROOT"], 'ssl/domains/%s_certifiate.pem' % safe_domain_name(domain))
		os.makedirs(os.path.dirname(ssl_certificate), exist_ok=True)
		if not os.path.exists(ssl_certificate):
			# Generate a new self-signed certificate using the same private key that we already have.

			# Start with a CSR.
			csr = os.path.join(env["STORAGE_ROOT"], 'ssl/domains/%s_cert_sign_req.csr' % safe_domain_name(domain))
			shell("check_call", [
				"openssl", "req", "-new",
				"-key", ssl_key,
				"-out",  csr,
				"-subj", "/C=%s/ST=/L=/O=/CN=%s" % (env["CSR_COUNTRY"], domain)])

			# And then make the certificate.
			shell("check_call", [
				"openssl", "x509", "-req",
				"-days", "365",
				"-in", csr,
				"-signkey", ssl_key,
				"-out", ssl_certificate])

	# Replace substitution strings in the template & return.
	nginx_conf = template
	nginx_conf = nginx_conf.replace("$HOSTNAME", domain)
	nginx_conf = nginx_conf.replace("$ROOT", root)
	nginx_conf = nginx_conf.replace("$SSL_KEY", ssl_key)
	nginx_conf = nginx_conf.replace("$SSL_CERTIFICATE", ssl_certificate)
	return nginx_conf
