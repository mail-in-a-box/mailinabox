# Creates an nginx configuration file so we serve HTTP/HTTPS on all
# domains for which a mail account has been set up.
########################################################################

import os, os.path

from mailconfig import get_mail_domains
from utils import shell, safe_domain_name, sort_domains

def get_web_domains(env):
	# What domains should we serve HTTP/HTTPS for?
	domains = set()

	# Add all domain names in use by email users and mail aliases.
	domains |= get_mail_domains(env)

	# Ensure the PRIMARY_HOSTNAME is in the list.
	domains.add(env['PRIMARY_HOSTNAME'])

	# Sort the list. Put PRIMARY_HOSTNAME first so it becomes the
	# default server (nginx's default_server).
	domains = sort_domains(domains, env)

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

	# Where will its root directory be for static files?

	root = get_web_root(domain, env)

	# What private key and SSL certificate will we use for this domain?
	ssl_key, ssl_certificate, csr_path = get_domain_ssl_files(domain, env)

	# For hostnames created after the initial setup, ensure we have an SSL certificate
	# available. Make a self-signed one now if one doesn't exist.
	ensure_ssl_certificate_exists(domain, ssl_key, ssl_certificate, csr_path, env)

	# Replace substitution strings in the template & return.
	nginx_conf = template
	nginx_conf = nginx_conf.replace("$HOSTNAME", domain)
	nginx_conf = nginx_conf.replace("$ROOT", root)
	nginx_conf = nginx_conf.replace("$SSL_KEY", ssl_key)
	nginx_conf = nginx_conf.replace("$SSL_CERTIFICATE", ssl_certificate)
	return nginx_conf

def get_web_root(domain, env):
	# Try STORAGE_ROOT/web/domain_name if it exists, but fall back to STORAGE_ROOT/web/default.
	for test_domain in (domain, 'default'):
		root = os.path.join(env["STORAGE_ROOT"], "www", safe_domain_name(test_domain))
		if os.path.exists(root): break
	return root

def get_domain_ssl_files(domain, env):
	# What SSL private key will we use? Allow the user to override this, but
	# in many cases using the same private key for all domains would be fine.
	# Don't allow the user to override the key for PRIMARY_HOSTNAME because
	# that's what's in the main file.
	ssl_key = os.path.join(env["STORAGE_ROOT"], 'ssl/ssl_private_key.pem')
	alt_key = os.path.join(env["STORAGE_ROOT"], 'ssl/domains/%s_private_key.pem' % safe_domain_name(domain))
	if domain != env['PRIMARY_HOSTNAME'] and os.path.exists(alt_key):
		ssl_key = alt_key

	# What SSL certificate will we use? This has to be differnet for each
	# domain name. For PRIMARY_HOSTNAME, use the one we generated at set-up
	# time.
	if domain == env['PRIMARY_HOSTNAME']:
		ssl_certificate = os.path.join(env["STORAGE_ROOT"], 'ssl/ssl_certificate.pem')
	else:
		ssl_certificate = os.path.join(env["STORAGE_ROOT"], 'ssl/domains/%s_certifiate.pem' % safe_domain_name(domain))

	# Where would the CSR go? As with the SSL cert itself, the CSR must be
	# different for each domain name.
	if domain == env['PRIMARY_HOSTNAME']:
		csr_path = os.path.join(env["STORAGE_ROOT"], 'ssl/ssl_cert_sign_req.csr')
	else:
		csr_path = os.path.join(env["STORAGE_ROOT"], 'ssl/domains/%s_cert_sign_req.csr' % safe_domain_name(domain))

	return ssl_key, ssl_certificate, csr_path

def ensure_ssl_certificate_exists(domain, ssl_key, ssl_certificate, csr_path, env):
	# For domains besides PRIMARY_HOSTNAME, generate a self-signed certificate if one doesn't
	# already exist. See setup/mail.sh for documentation.

	if domain == env['PRIMARY_HOSTNAME']:
		return

	if os.path.exists(ssl_certificate):
		return

	os.makedirs(os.path.dirname(ssl_certificate), exist_ok=True)

	# Generate a new self-signed certificate using the same private key that we already have.

	# Start with a CSR.
	shell("check_call", [
		"openssl", "req", "-new",
		"-key", ssl_key,
		"-out",  csr_path,
		"-subj", "/C=%s/ST=/L=/O=/CN=%s" % (env["CSR_COUNTRY"], domain)])

	# And then make the certificate.
	shell("check_call", [
		"openssl", "x509", "-req",
		"-days", "365",
		"-in", csr_path,
		"-signkey", ssl_key,
		"-out", ssl_certificate])

