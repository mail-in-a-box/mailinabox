#!/usr/local/lib/mailinabox/env/bin/python
# Utilities for installing and selecting SSL certificates.

import os, os.path, re, shutil, subprocess, tempfile

from utils import shell, safe_domain_name, sort_domains
import idna

# SELECTING SSL CERTIFICATES FOR USE IN WEB

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
		if not os.path.exists(ssl_root):
			return
		for fn in os.listdir(ssl_root):
			if fn == 'ssl_certificate.pem':
				# This is always a symbolic link
				# to the certificate to use for
				# PRIMARY_HOSTNAME. Don't let it
				# be eligible for use because we
				# could end up creating a symlink
				# to itself --- we want to find
				# the cert that it should be a
				# symlink to.
				continue
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
			# The primary hostname can only use a certificate mapped
			# to the system private key.
			if domain == env['PRIMARY_HOSTNAME']:
				if cert._private_key._filename != os.path.join(env['STORAGE_ROOT'], 'ssl', 'ssl_private_key.pem'):
					continue

			domains.setdefault(domain, []).append(cert)

	# Sort the certificates to prefer good ones.
	import datetime
	now = datetime.datetime.utcnow()
	ret = { }
	for domain, cert_list in domains.items():
		#for c in cert_list: print(domain, c.not_valid_before, c.not_valid_after, "("+str(now)+")", c.issuer, c.subject, c._filename)
		cert_list.sort(key = lambda cert : (
			# must be valid NOW
			cert.not_valid_before <= now <= cert.not_valid_after,

			# prefer one that is not self-signed
			cert.issuer != cert.subject,

                        # prefer one that is not our temporary ca
			"Temporary-Mail-In-A-Box-CA" not in "%s" % cert.issuer.rdns,

			###########################################################
			# The above lines ensure that valid certificates are chosen
			# over invalid certificates. The lines below choose between
			# multiple valid certificates available for this domain.
			###########################################################

			# prefer one with the expiration furthest into the future so
			# that we can easily rotate to new certs as we get them
			cert.not_valid_after,

			###########################################################
			# We always choose the certificate that is good for the
			# longest period of time. This is important for how we
			# provision certificates for Let's Encrypt. To ensure that
			# we don't re-provision every night, we have to ensure that
			# if we choose to provison a certificate that it will
			# *actually* be used so the provisioning logic knows it
			# doesn't still need to provision a certificate for the
			# domain.
			###########################################################

			# in case a certificate is installed in multiple paths,
			# prefer the... lexicographically last one?
			cert._filename,

		), reverse=True)
		cert = cert_list.pop(0)
		ret[domain] = {
			"private-key": cert._private_key._filename,
			"certificate": cert._filename,
			"primary-domain": cert._primary_domain,
			"certificate_object": cert,
			}

	return ret

def get_domain_ssl_files(domain, ssl_certificates, env, allow_missing_cert=False, use_main_cert=True):
	if use_main_cert or not allow_missing_cert:
		# Get the system certificate info.
		ssl_private_key = os.path.join(os.path.join(env["STORAGE_ROOT"], 'ssl', 'ssl_private_key.pem'))
		ssl_certificate = os.path.join(os.path.join(env["STORAGE_ROOT"], 'ssl', 'ssl_certificate.pem'))
		system_certificate = {
			"private-key": ssl_private_key,
			"certificate": ssl_certificate,
			"primary-domain": env['PRIMARY_HOSTNAME'],
			"certificate_object": load_pem(load_cert_chain(ssl_certificate)[0]),
		}

	if use_main_cert:
		if domain == env['PRIMARY_HOSTNAME']:
			# The primary domain must use the server certificate because
			# it is hard-coded in some service configuration files.
			return system_certificate

	wildcard_domain = re.sub("^[^\.]+", "*", domain)
	if domain in ssl_certificates:
		return ssl_certificates[domain]
	elif wildcard_domain in ssl_certificates:
		return ssl_certificates[wildcard_domain]
	elif not allow_missing_cert:
		# No valid certificate is available for this domain! Return default files.
		return system_certificate
	else:
		# No valid certificate is available for this domain.
		return None


# PROVISIONING CERTIFICATES FROM LETSENCRYPT

def get_certificates_to_provision(env, limit_domains=None, show_valid_certs=True):
	# Get a set of domain names that we can provision certificates for
	# using certbot. We start with domains that the box is serving web
	# for and subtract:
	# * domains not in limit_domains if limit_domains is not empty
	# * domains with custom "A" records, i.e. they are hosted elsewhere
	# * domains with actual "A" records that point elsewhere (misconfiguration)
	# * domains that already have certificates that will be valid for a while

	from web_update import get_web_domains
	from status_checks import query_dns, normalize_ip

	existing_certs = get_ssl_certificates(env)

	plausible_web_domains = get_web_domains(env, exclude_dns_elsewhere=False)
	actual_web_domains = get_web_domains(env)

	domains_to_provision = set()
	domains_cant_provision = { }

	for domain in plausible_web_domains:
		# Skip domains that the user doesn't want to provision now.
		if limit_domains and domain not in limit_domains:
			continue

		# Check that there isn't an explicit A/AAAA record.
		if domain not in actual_web_domains:
			domains_cant_provision[domain] = "The domain has a custom DNS A/AAAA record that points the domain elsewhere, so there is no point to installing a TLS certificate here and we could not automatically provision one anyway because provisioning requires access to the website (which isn't here)."

		# Check that the DNS resolves to here.
		else:

			# Does the domain resolve to this machine in public DNS? If not,
			# we can't do domain control validation. For IPv6 is configured,
			# make sure both IPv4 and IPv6 are correct because we don't know
			# how Let's Encrypt will connect.
			bad_dns = []
			for rtype, value in [("A", env["PUBLIC_IP"]), ("AAAA", env.get("PUBLIC_IPV6"))]:
				if not value: continue # IPv6 is not configured
				response = query_dns(domain, rtype)
				if response != normalize_ip(value):
					bad_dns.append("%s (%s)" % (response, rtype))
	
			if bad_dns:
				domains_cant_provision[domain] = "The domain name does not resolve to this machine: " \
					+ (", ".join(bad_dns)) \
					+ "."
			
			else:
				# DNS is all good.

				# Check for a good existing cert.
				existing_cert = get_domain_ssl_files(domain, existing_certs, env, use_main_cert=False, allow_missing_cert=True)
				if existing_cert:
					existing_cert_check = check_certificate(domain, existing_cert['certificate'], existing_cert['private-key'],
						warn_if_expiring_soon=14)
					if existing_cert_check[0] == "OK":
						if show_valid_certs:
							domains_cant_provision[domain] = "The domain has a valid certificate already. ({} Certificate: {}, private key {})".format(
								existing_cert_check[1],
								existing_cert['certificate'],
								existing_cert['private-key'])
						continue

				domains_to_provision.add(domain)

	return (domains_to_provision, domains_cant_provision)

def provision_certificates(env, limit_domains):
	# What domains should we provision certificates for? And what
	# errors prevent provisioning for other domains.
	domains, domains_cant_provision = get_certificates_to_provision(env, limit_domains=limit_domains)

	# Build a list of what happened on each domain or domain-set.
	ret = []
	for domain, error in domains_cant_provision.items():
		ret.append({
			"domains": [domain],
			"log": [error],
			"result": "skipped",
		})

	# Break into groups by DNS zone: Group every domain with its parent domain, if
	# its parent domain is in the list of domains to request a certificate for.
	# Start with the zones so that if the zone doesn't need a certificate itself,
	# its children will still be grouped together. Sort the provision domains to
	# put parents ahead of children.
	# Since Let's Encrypt requests are limited to 100 domains at a time,
	# we'll create a list of lists of domains where the inner lists have
	# at most 100 items. By sorting we also get the DNS zone domain as the first
	# entry in each list (unless we overflow beyond 100) which ends up as the
	# primary domain listed in each certificate.
	from dns_update import get_dns_zones
	certs = { }
	for zone, zonefile in get_dns_zones(env):
		certs[zone] = [[]]
	for domain in sort_domains(domains, env):
		# Does the domain end with any domain we've seen so far.
		for parent in certs.keys():
			if domain.endswith("." + parent):
				# Add this to the parent's list of domains.
				# Start a new group if the list already has
				# 100 items.
				if len(certs[parent][-1]) == 100:
					certs[parent].append([])
				certs[parent][-1].append(domain)
				break
		else:
			# This domain is not a child of any domain we've seen yet, so
			# start a new group. This shouldn't happen since every zone
			# was already added.
			certs[domain] = [[domain]]

	# Flatten to a list of lists of domains (from a mapping). Remove empty
	# lists (zones with no domains that need certs).
	certs = sum(certs.values(), [])
	certs = [_ for _ in certs if len(_) > 0]

	# Prepare to provision.

	# Where should we put our Let's Encrypt account info and state cache.
	account_path = os.path.join(env['STORAGE_ROOT'], 'ssl/lets_encrypt')
	if not os.path.exists(account_path):
		os.mkdir(account_path)

	# Provision certificates.
	for domain_list in certs:
		ret.append({
			"domains": domain_list,
			"log": [],
		})
		try:
			# Create a CSR file for our master private key so that certbot
			# uses our private key.
			key_file = os.path.join(env['STORAGE_ROOT'], 'ssl', 'ssl_private_key.pem')
			with tempfile.NamedTemporaryFile() as csr_file:
				# We could use openssl, but certbot requires
				# that the CN domain and SAN domains match
				# the domain list passed to certbot, and adding
				# SAN domains openssl req is ridiculously complicated.
				# subprocess.check_output([
				# 	"openssl", "req", "-new",
				# 	"-key", key_file,
				# 	"-out", csr_file.name,
				# 	"-subj", "/CN=" + domain_list[0],
				# 	"-sha256" ])
				from cryptography import x509
				from cryptography.hazmat.backends import default_backend
				from cryptography.hazmat.primitives.serialization import Encoding
				from cryptography.hazmat.primitives import hashes
				from cryptography.x509.oid import NameOID
				builder = x509.CertificateSigningRequestBuilder()
				builder = builder.subject_name(x509.Name([ x509.NameAttribute(NameOID.COMMON_NAME, domain_list[0]) ]))
				builder = builder.add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
				builder = builder.add_extension(x509.SubjectAlternativeName(
					[x509.DNSName(d) for d in domain_list]
				), critical=False)
				request = builder.sign(load_pem(load_cert_chain(key_file)[0]), hashes.SHA256(), default_backend())
				with open(csr_file.name, "wb") as f:
					f.write(request.public_bytes(Encoding.PEM))

				# Provision, writing to a temporary file.
				webroot = os.path.join(account_path, 'webroot')
				os.makedirs(webroot, exist_ok=True)
				with tempfile.TemporaryDirectory() as d:
					cert_file = os.path.join(d, 'cert_and_chain.pem')
					print("Provisioning TLS certificates for " + ", ".join(domain_list) + ".")
					certbotret = subprocess.check_output([
						"certbot",
						"certonly",
						#"-v", # just enough to see ACME errors
						"--non-interactive", # will fail if user hasn't registered during Mail-in-a-Box setup

						"-d", ",".join(domain_list), # first will be main domain

						"--csr", csr_file.name, # use our private key; unfortunately this doesn't work with auto-renew so we need to save cert manually
						"--cert-path", os.path.join(d, 'cert'), # we only use the full chain
						"--chain-path", os.path.join(d, 'chain'), # we only use the full chain
						"--fullchain-path", cert_file,

						"--webroot", "--webroot-path", webroot,

						"--config-dir", account_path,
						#"--staging",
					], stderr=subprocess.STDOUT).decode("utf8")
					install_cert_copy_file(cert_file, env)

			ret[-1]["log"].append(certbotret)
			ret[-1]["result"] = "installed"
		except subprocess.CalledProcessError as e:
			ret[-1]["log"].append(e.output.decode("utf8"))
			ret[-1]["result"] = "error"
		except Exception as e:
			ret[-1]["log"].append(str(e))
			ret[-1]["result"] = "error"

	# Run post-install steps.
	ret.extend(post_install_func(env))

	# Return what happened with each certificate request.
	return ret

def provision_certificates_cmdline():
	import sys
	from exclusiveprocess import Lock

	from utils import load_environment

	Lock(die=True).forever()
	env = load_environment()

	quiet = False
	domains = []

	for arg in sys.argv[1:]:
		if arg == "-q":
			quiet = True
		else:
			domains.append(arg)

	# Go.
	status = provision_certificates(env, limit_domains=domains)

	# Show what happened.
	for request in status:
		if isinstance(request, str):
			print(request)
		else:
			if quiet and request['result'] == 'skipped':
				continue
			print(request['result'] + ":", ", ".join(request['domains']) + ":")
			for line in request["log"]:
				print(line)
			print()


# INSTALLING A NEW CERTIFICATE FROM THE CONTROL PANEL

def create_csr(domain, ssl_key, country_code, env):
	return shell("check_output", [
				"openssl", "req", "-new",
				"-key", ssl_key,
				"-sha256",
				"-subj", "/C=%s/CN=%s" % (country_code, domain)])

def install_cert(domain, ssl_cert, ssl_chain, env, raw=False):
	# Write the combined cert+chain to a temporary path and validate that it is OK.
	# The certificate always goes above the chain.
	import tempfile
	fd, fn = tempfile.mkstemp('.pem')
	os.write(fd, (ssl_cert + '\n' + ssl_chain).encode("ascii"))
	os.close(fd)

	# Do validation on the certificate before installing it.
	ssl_private_key = os.path.join(os.path.join(env["STORAGE_ROOT"], 'ssl', 'ssl_private_key.pem'))
	cert_status, cert_status_details = check_certificate(domain, fn, ssl_private_key)
	if cert_status != "OK":
		if cert_status == "SELF-SIGNED":
			cert_status = "This is a self-signed certificate. I can't install that."
		os.unlink(fn)
		if cert_status_details is not None:
			cert_status += " " + cert_status_details
		return cert_status

	# Copy certifiate into ssl directory.
	install_cert_copy_file(fn, env)

	# Run post-install steps.
	ret = post_install_func(env)
	if raw: return ret
	return "\n".join(ret)


def install_cert_copy_file(fn, env):
	# Where to put it?
	# Make a unique path for the certificate.
	from cryptography.hazmat.primitives import hashes
	from binascii import hexlify
	cert = load_pem(load_cert_chain(fn)[0])
	all_domains, cn = get_certificate_domains(cert)
	path = "%s-%s-%s.pem" % (
		safe_domain_name(cn), # common name, which should be filename safe because it is IDNA-encoded, but in case of a malformed cert make sure it's ok to use as a filename
		cert.not_valid_after.date().isoformat().replace("-", ""), # expiration date
		hexlify(cert.fingerprint(hashes.SHA256())).decode("ascii")[0:8], # fingerprint prefix
		)
	ssl_certificate = os.path.join(os.path.join(env["STORAGE_ROOT"], 'ssl', path))

	# Install the certificate.
	os.makedirs(os.path.dirname(ssl_certificate), exist_ok=True)
	shutil.move(fn, ssl_certificate)


def post_install_func(env):
	ret = []

	# Get the certificate to use for PRIMARY_HOSTNAME.
	ssl_certificates = get_ssl_certificates(env)
	cert = get_domain_ssl_files(env['PRIMARY_HOSTNAME'], ssl_certificates, env, use_main_cert=False)
	if not cert:
		# Ruh-row, we don't have any certificate usable
		# for the primary hostname.
		ret.append("there is no valid certificate for " + env['PRIMARY_HOSTNAME'])

	# Symlink the best cert for PRIMARY_HOSTNAME to the system
	# certificate path, which is hard-coded for various purposes, and then
	# restart postfix, dovecot and openldap.
	system_ssl_certificate = os.path.join(os.path.join(env["STORAGE_ROOT"], 'ssl', 'ssl_certificate.pem'))
	if cert and os.readlink(system_ssl_certificate) != cert['certificate']:
		# Update symlink.
		ret.append("updating primary certificate")
		ssl_certificate = cert['certificate']
		os.unlink(system_ssl_certificate)
		os.symlink(ssl_certificate, system_ssl_certificate)

		# Restart postfix and dovecot so they pick up the new file.
		shell('check_call', ["/usr/sbin/service", "slapd", "restart"])
		shell('check_call', ["/usr/sbin/service", "postfix", "restart"])
		shell('check_call', ["/usr/sbin/service", "dovecot", "restart"])
		ret.append("mail services restarted")

		# The DANE TLSA record will remain valid so long as the private key
		# hasn't changed. We don't ever change the private key automatically.
		# If the user does it, they must manually update DNS.

	# Update the web configuration so nginx picks up the new certificate file.
	from web_update import do_web_update
	ret.append( do_web_update(env) )

	return ret

# VALIDATION OF CERTIFICATES

def check_certificate(domain, ssl_certificate, ssl_private_key, warn_if_expiring_soon=10, rounded_time=False, just_check_domain=False):
	# Check that the ssl_certificate & ssl_private_key files are good
	# for the provided domain.

	from cryptography.hazmat.primitives.asymmetric.rsa import RSAPrivateKey
	from cryptography.x509 import Certificate

	# The ssl_certificate file may contain a chain of certificates. We'll
	# need to split that up before we can pass anything to openssl or
	# parse them in Python. Parse it with the cryptography library.
	try:
		ssl_cert_chain = load_cert_chain(ssl_certificate)
		cert = load_pem(ssl_cert_chain[0])
		if not isinstance(cert, Certificate): raise ValueError("This is not a certificate file.")
	except ValueError as e:
		return ("There is a problem with the certificate file: %s" % str(e), None)

	# First check that the domain name is one of the names allowed by
	# the certificate.
	if domain is not None:
		certificate_names, cert_primary_name = get_certificate_domains(cert)

		# Check that the domain appears among the acceptable names, or a wildcard
		# form of the domain name (which is a stricter check than the specs but
		# should work in normal cases).
		wildcard_domain = re.sub("^[^\.]+", "*", domain)
		if domain not in certificate_names and wildcard_domain not in certificate_names:
			return ("The certificate is for the wrong domain name. It is for %s."
				% ", ".join(sorted(certificate_names)), None)

	# Second, check that the certificate matches the private key.
	if ssl_private_key is not None:
		try:
			priv_key = load_pem(open(ssl_private_key, 'rb').read())
		except ValueError as e:
			return ("The private key file %s is not a private key file: %s" % (ssl_private_key, str(e)), None)

		if not isinstance(priv_key, RSAPrivateKey):
			return ("The private key file %s is not a private key file." % ssl_private_key, None)

		if priv_key.public_key().public_numbers() != cert.public_key().public_numbers():
			return ("The certificate does not correspond to the private key at %s." % ssl_private_key, None)

		# We could also use the openssl command line tool to get the modulus
		# listed in each file. The output of each command below looks like "Modulus=XXXXX".
		# $ openssl rsa -inform PEM -noout -modulus -in ssl_private_key
		# $ openssl x509 -in ssl_certificate -noout -modulus

	# Third, check if the certificate is self-signed. Return a special flag string.
	if cert.issuer == cert.subject:
		return ("SELF-SIGNED", None)

	elif "Temporary-Mail-In-A-Box-CA" in "%s" % cert.issuer.rdns:
		return ("SELF-SIGNED", None)

	# When selecting which certificate to use for non-primary domains, we check if the primary
	# certificate or a www-parent-domain certificate is good for the domain. There's no need
	# to run extra checks beyond this point.
	if just_check_domain:
		return ("OK", None)

	# Check that the certificate hasn't expired. The datetimes returned by the
	# certificate are 'naive' and in UTC. We need to get the current time in UTC.
	import datetime
	now = datetime.datetime.utcnow()
	if not(cert.not_valid_before <= now <= cert.not_valid_after):
		return ("The certificate has expired or is not yet valid. It is valid from %s to %s." % (cert.not_valid_before, cert.not_valid_after), None)

	# Next validate that the certificate is valid. This checks whether the certificate
	# is self-signed, that the chain of trust makes sense, that it is signed by a CA
	# that Ubuntu has installed on this machine's list of CAs, and I think that it hasn't
	# expired.

	# The certificate chain has to be passed separately and is given via STDIN.
	# This command returns a non-zero exit status in most cases, so trap errors.
	retcode, verifyoutput = shell('check_output', [
		"openssl",
		"verify", "-verbose",
		"-purpose", "sslserver", "-policy_check",]
		+ ([] if len(ssl_cert_chain) == 1 else ["-untrusted", "/proc/self/fd/0"])
		+ [ssl_certificate],
		input=b"\n\n".join(ssl_cert_chain[1:]),
		trap=True)

	if "self signed" in verifyoutput:
		# Certificate is self-signed. Probably we detected this above.
		return ("SELF-SIGNED", None)

	elif retcode != 0:
		if "unable to get local issuer certificate" in verifyoutput:
			return ("The certificate is missing an intermediate chain or the intermediate chain is incorrect or incomplete. (%s)" % verifyoutput, None)

		# There is some unknown problem. Return the `openssl verify` raw output.
		return ("There is a problem with the certificate.", verifyoutput.strip())

	else:
		# `openssl verify` returned a zero exit status so the cert is currently
		# good.

		# But is it expiring soon?
		cert_expiration_date = cert.not_valid_after
		ndays = (cert_expiration_date-now).days
		if not rounded_time or ndays <= 10:
			# Yikes better renew soon!
			expiry_info = "The certificate expires in %d days on %s." % (ndays, cert_expiration_date.strftime("%x"))
		else:
			# We'll renew it with Lets Encrypt.
			expiry_info = "The certificate expires on %s." % cert_expiration_date.strftime("%x")

		if warn_if_expiring_soon and ndays <= warn_if_expiring_soon:
			# Warn on day 10 to give 4 days for us to automatically renew the
			# certificate, which occurs on day 14.
			return ("The certificate is expiring soon: " + expiry_info, None)

		# Return the special OK code.
		return ("OK", expiry_info)

def load_cert_chain(pemfile):
	# A certificate .pem file may contain a chain of certificates.
	# Load the file and split them apart.
	re_pem = rb"(-+BEGIN (?:.+)-+[\r\n]+(?:[A-Za-z0-9+/=]{1,64}[\r\n]+)+-+END (?:.+)-+[\r\n]+)"
	with open(pemfile, "rb") as f:
		pem = f.read() + b"\n" # ensure trailing newline
		pemblocks = re.findall(re_pem, pem)
		if len(pemblocks) == 0:
			raise ValueError("File does not contain valid PEM data.")
		return pemblocks

def load_pem(pem):
	# Parse a "---BEGIN .... END---" PEM string and return a Python object for it
	# using classes from the cryptography package.
	from cryptography.x509 import load_pem_x509_certificate
	from cryptography.hazmat.primitives import serialization
	from cryptography.hazmat.backends import default_backend
	pem_type = re.match(b"-+BEGIN (.*?)-+[\r\n]", pem)
	if pem_type is None:
		raise ValueError("File is not a valid PEM-formatted file.")
	pem_type = pem_type.group(1)
	if pem_type in (b"RSA PRIVATE KEY", b"PRIVATE KEY"):
		return serialization.load_pem_private_key(pem, password=None, backend=default_backend())
	if pem_type == b"CERTIFICATE":
		return load_pem_x509_certificate(pem, default_backend())
	raise ValueError("Unsupported PEM object type: " + pem_type.decode("ascii", "replace"))

def get_certificate_domains(cert):
	from cryptography.x509 import DNSName, ExtensionNotFound, OID_COMMON_NAME, OID_SUBJECT_ALTERNATIVE_NAME
	import idna

	names = set()
	cn = None

	# The domain may be found in the Subject Common Name (CN). This comes back as an IDNA (ASCII)
	# string, which is the format we store domains in - so good.
	try:
		cn = cert.subject.get_attributes_for_oid(OID_COMMON_NAME)[0].value
		names.add(cn)
	except IndexError:
		# No common name? Certificate is probably generated incorrectly.
		# But we'll let it error-out when it doesn't find the domain.
		pass

	# ... or be one of the Subject Alternative Names. The cryptography library handily IDNA-decodes
	# the names for us. We must encode back to ASCII, but wildcard certificates can't pass through
	# IDNA encoding/decoding so we must special-case. See https://github.com/pyca/cryptography/pull/2071.
	def idna_decode_dns_name(dns_name):
		if dns_name.startswith("*."):
			return "*." + idna.encode(dns_name[2:]).decode('ascii')
		else:
			return idna.encode(dns_name).decode('ascii')

	try:
		sans = cert.extensions.get_extension_for_oid(OID_SUBJECT_ALTERNATIVE_NAME).value.get_values_for_type(DNSName)
		for san in sans:
			names.add(idna_decode_dns_name(san))
	except ExtensionNotFound:
		pass

	return names, cn

if __name__  == "__main__":
	# Provision certificates.
	provision_certificates_cmdline()
