# Utilities for installing and selecting SSL certificates.

import os, os.path, re, shutil

from utils import shell, safe_domain_name

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

	ret = ["OK"]

	# When updating the cert for PRIMARY_HOSTNAME, symlink it from the system
	# certificate path, which is hard-coded for various purposes, and then
	# restart postfix and dovecot.
	if domain == env['PRIMARY_HOSTNAME']:
		# Update symlink.
		system_ssl_certificate = os.path.join(os.path.join(env["STORAGE_ROOT"], 'ssl', 'ssl_certificate.pem'))
		os.unlink(system_ssl_certificate)
		os.symlink(ssl_certificate, system_ssl_certificate)

		# Restart postfix and dovecot so they pick up the new file.
		shell('check_call', ["/usr/sbin/service", "postfix", "restart"])
		shell('check_call', ["/usr/sbin/service", "dovecot", "restart"])
		ret.append("mail services restarted")

		# The DANE TLSA record will remain valid so long as the private key
		# hasn't changed. We don't ever change the private key automatically.
		# If the user does it, they must manually update DNS.

	# Update the web configuration so nginx picks up the new certificate file.
	from web_update import do_web_update
	ret.append( do_web_update(env) )
	return "\n".join(ret)


def check_certificate(domain, ssl_certificate, ssl_private_key, warn_if_expiring_soon=True, rounded_time=False, just_check_domain=False):
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
		return ("There is a problem with the SSL certificate.", verifyoutput.strip())

	else:
		# `openssl verify` returned a zero exit status so the cert is currently
		# good.

		# But is it expiring soon?
		cert_expiration_date = cert.not_valid_after
		ndays = (cert_expiration_date-now).days
		if not rounded_time or ndays < 7:
			expiry_info = "The certificate expires in %d days on %s." % (ndays, cert_expiration_date.strftime("%x"))
		elif ndays <= 14:
			expiry_info = "The certificate expires in less than two weeks, on %s." % cert_expiration_date.strftime("%x")
		elif ndays <= 31:
			expiry_info = "The certificate expires in less than a month, on %s." % cert_expiration_date.strftime("%x")
		else:
			expiry_info = "The certificate expires on %s." % cert_expiration_date.strftime("%x")

		if ndays <= 31 and warn_if_expiring_soon:
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
