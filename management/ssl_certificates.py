#!/usr/bin/python3
# Utilities for installing and selecting SSL certificates.

import os, os.path, re, shutil

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

def get_domain_ssl_files(domain, ssl_certificates, env, allow_missing_cert=False, raw=False):
	# Get the system certificate info.
	ssl_private_key = os.path.join(os.path.join(env["STORAGE_ROOT"], 'ssl', 'ssl_private_key.pem'))
	ssl_certificate = os.path.join(os.path.join(env["STORAGE_ROOT"], 'ssl', 'ssl_certificate.pem'))
	system_certificate = {
		"private-key": ssl_private_key,
		"certificate": ssl_certificate,
		"primary-domain": env['PRIMARY_HOSTNAME'],
		"certificate_object": load_pem(load_cert_chain(ssl_certificate)[0]),
	}

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

def get_certificates_to_provision(env, show_extended_problems=True, force_domains=None):
	# Get a set of domain names that we should now provision certificates
	# for. Provision if a domain name has no valid certificate or if any
	# certificate is expiring in 14 days. If provisioning anything, also
	# provision certificates expiring within 30 days. The period between
	# 14 and 30 days allows us to consolidate domains into multi-domain
	# certificates for domains expiring around the same time.

	from web_update import get_web_domains

	import datetime
	now = datetime.datetime.utcnow()

	# Get domains with missing & expiring certificates.
	certs = get_ssl_certificates(env)
	domains = set()
	domains_if_any = set()
	problems = { }
	for domain in get_web_domains(env):
		# If the user really wants a cert for certain domains, include it.
		if force_domains:
			if force_domains == "ALL" or (isinstance(force_domains, list) and domain in force_domains):
				domains.add(domain)
			continue

		# Include this domain if its certificate is missing, self-signed, or expiring soon.
		try:
			cert = get_domain_ssl_files(domain, certs, env, allow_missing_cert=True)
		except FileNotFoundError as e:
			# system certificate is not present
			problems[domain] = "Error: " + str(e)
			continue
		if cert is None:
			# No valid certificate available.
			domains.add(domain)
		else:
			cert = cert["certificate_object"]
			if cert.issuer == cert.subject:
				# This is self-signed. Get a real one.
				domains.add(domain)
			
			# Valid certificate today, but is it expiring soon?
			elif cert.not_valid_after-now < datetime.timedelta(days=14):
				domains.add(domain)
			elif cert.not_valid_after-now < datetime.timedelta(days=30):
				domains_if_any.add(domain)

			# It's valid. Should we report its validness?
			elif show_extended_problems:
				problems[domain] = "The certificate is valid for at least another 30 days --- no need to replace."

	# Warn the user about domains hosted elsewhere.
	if not force_domains and show_extended_problems:
		for domain in set(get_web_domains(env, exclude_dns_elsewhere=False)) - set(get_web_domains(env)):
			problems[domain] = "The domain's DNS is pointed elsewhere, so there is no point to installing a TLS certificate here and we could not automatically provision one anyway because provisioning requires access to the website (which isn't here)."

	# Filter out domains that we can't provision a certificate for.
	def can_provision_for_domain(domain):
		# Let's Encrypt doesn't yet support IDNA domains.
		# We store domains in IDNA (ASCII). To see if this domain is IDNA,
		# we'll see if its IDNA-decoded form is different.
		if idna.decode(domain.encode("ascii")) != domain:
			problems[domain] = "Let's Encrypt does not yet support provisioning certificates for internationalized domains."
			return False

		# Does the domain resolve to this machine in public DNS? If not,
		# we can't do domain control validation. For IPv6 is configured,
		# make sure both IPv4 and IPv6 are correct because we don't know
		# how Let's Encrypt will connect.
		import dns.resolver
		for rtype, value in [("A", env["PUBLIC_IP"]), ("AAAA", env.get("PUBLIC_IPV6"))]:
			if not value: continue # IPv6 is not configured
			try:
				# Must make the qname absolute to prevent a fall-back lookup with a
				# search domain appended, by adding a period to the end.
				response = dns.resolver.query(domain + ".", rtype)
			except (dns.resolver.NoNameservers, dns.resolver.NXDOMAIN, dns.resolver.NoAnswer) as e:
				problems[domain] = "DNS isn't configured properly for this domain: DNS resolution failed (%s: %s)." % (rtype, str(e) or repr(e)) # NoAnswer's str is empty
				return False
			except Exception as e:
				problems[domain] = "DNS isn't configured properly for this domain: DNS lookup had an error: %s." % str(e)
				return False
			if len(response) != 1 or str(response[0]) != value:
				problems[domain] = "Domain control validation cannot be performed for this domain because DNS points the domain to another machine (%s %s)." % (rtype, ", ".join(str(r) for r in response))
				return False

		return True

	domains = set(filter(can_provision_for_domain, domains))

	# If there are any domains we definitely will provision for, add in
	# additional domains to do at this time.
	if len(domains) > 0:
		domains |= set(filter(can_provision_for_domain, domains_if_any))

	return (domains, problems)

def provision_certificates(env, agree_to_tos_url=None, logger=None, show_extended_problems=True, force_domains=None, jsonable=False):
	import requests.exceptions
	import acme.messages

	from free_tls_certificates import client

	# What domains should we provision certificates for? And what
	# errors prevent provisioning for other domains.
	domains, problems = get_certificates_to_provision(env, force_domains=force_domains, show_extended_problems=show_extended_problems)

	# Exit fast if there is nothing to do.
	if len(domains) == 0:
		return {
			"requests": [],
			"problems": problems,
		}

	# Break into groups of up to 100 certificates at a time, which is Let's Encrypt's
	# limit for a single certificate. We'll sort to put related domains together.
	domains = sort_domains(domains, env)
	certs = []
	while len(domains) > 0:
		certs.append( domains[0:100] )
		domains = domains[100:]

	# Prepare to provision.

	# Where should we put our Let's Encrypt account info and state cache.
	account_path = os.path.join(env['STORAGE_ROOT'], 'ssl/lets_encrypt')
	if not os.path.exists(account_path):
		os.mkdir(account_path)

	# Where should we put ACME challenge files. This is mapped to /.well-known/acme_challenge
	# by the nginx configuration.
	challenges_path = os.path.join(account_path, 'acme_challenges')
	if not os.path.exists(challenges_path):
		os.mkdir(challenges_path)

	# Read in the private key that we use for all TLS certificates. We'll need that
	# to generate a CSR (done by free_tls_certificates).
	with open(os.path.join(env['STORAGE_ROOT'], 'ssl/ssl_private_key.pem'), 'rb') as f:
		private_key = f.read()

	# Provision certificates.

	ret = []
	for domain_list in certs:
		# For return.
		ret_item = {
			"domains": domain_list,
			"log": [],
		}
		ret.append(ret_item)

		# Logging for free_tls_certificates.
		def my_logger(message):
			if logger: logger(message)
			ret_item["log"].append(message)

		# Attempt to provision a certificate.
		try:
			try:
				cert = client.issue_certificate(
					domain_list,
					account_path,
					agree_to_tos_url=agree_to_tos_url,
					private_key=private_key,
					logger=my_logger)

			except client.NeedToTakeAction as e:
				# Write out the ACME challenge files.
				for action in e.actions:
					if isinstance(action, client.NeedToInstallFile):
						fn = os.path.join(challenges_path, action.file_name)
						with open(fn, 'w') as f:
							f.write(action.contents)
					else:
						raise ValueError(str(action))

				# Try to provision now that the challenge files are installed.

				cert = client.issue_certificate(
					domain_list,
					account_path,
					private_key=private_key,
					logger=my_logger)

		except client.NeedToAgreeToTOS as e:
			# The user must agree to the Let's Encrypt terms of service agreement
			# before any further action can be taken.
			ret_item.update({
				"result": "agree-to-tos",
				"url": e.url,
			})

		except client.WaitABit as e:
			# We need to hold on for a bit before querying again to see if we can
			# acquire a provisioned certificate.
			import time, datetime
			ret_item.update({
				"result": "wait",
				"until": e.until_when if not jsonable else e.until_when.isoformat(),
				"seconds": (e.until_when - datetime.datetime.now()).total_seconds()
			})

		except client.AccountDataIsCorrupt as e:
			# This is an extremely rare condition.
			ret_item.update({
				"result": "error",
				"message": "Something unexpected went wrong. It looks like your local Let's Encrypt account data is corrupted. There was a problem with the file " + e.account_file_path + ".",
			})

		except (client.InvalidDomainName, client.NeedToTakeAction, client.ChallengeFailed, acme.messages.Error, requests.exceptions.RequestException) as e:
			ret_item.update({
				"result": "error",
				"message": "Something unexpected went wrong: " + str(e),
			})

		else:
			# A certificate was issued.

			install_status = install_cert(domain_list[0], cert['cert'].decode("ascii"), b"\n".join(cert['chain']).decode("ascii"), env, raw=True)

			# str indicates the certificate was not installed.
			if isinstance(install_status, str):
				ret_item.update({
					"result": "error",
					"message": "Something unexpected was wrong with the provisioned certificate: " + install_status,
				})
			else:
				# A list indicates success and what happened next.
				ret_item["log"].extend(install_status)
				ret_item.update({
					"result": "installed",
				})

	# Return what happened with each certificate request.
	return {
		"requests": ret,
		"problems": problems,
	}

def provision_certificates_cmdline():
	import sys
	from utils import load_environment, exclusive_process

	exclusive_process("update_tls_certificates")
	env = load_environment()

	verbose = False
	headless = False
	force_domains = None
	show_extended_problems = True
	
	args = list(sys.argv)
	args.pop(0) # program name
	if args and args[0] == "-v":
		verbose = True
		args.pop(0)
	if args and args[0] == "q":
		show_extended_problems = False
		args.pop(0)
	if args and args[0] == "--headless":
		headless = True
		args.pop(0)
	if args and args[0] == "--force":
		force_domains = "ALL"
		args.pop(0)
	else:
		force_domains = args

	agree_to_tos_url = None
	while True:
		# Run the provisioning script. This installs certificates. If there are
		# a very large number of domains on this box, it issues separate
		# certificates for groups of domains. We have to check the result for
		# each group.
		def my_logger(message):
			if verbose:
				print(">", message)
		status = provision_certificates(env, agree_to_tos_url=agree_to_tos_url, logger=my_logger, force_domains=force_domains, show_extended_problems=show_extended_problems)
		agree_to_tos_url = None # reset to prevent infinite looping

		if not status["requests"]:
			# No domains need certificates.
			if not headless or verbose:
				if len(status["problems"]) == 0:
					print("No domains hosted on this box need a new TLS certificate at this time.")
				elif len(status["problems"]) > 0:
					print("No TLS certificates could be provisoned at this time:")
					print()
					for domain in sort_domains(status["problems"], env):
						print("%s: %s" % (domain, status["problems"][domain]))

			sys.exit(0)

		# What happened?
		wait_until = None
		wait_domains = []
		for request in status["requests"]:
			if request["result"] == "agree-to-tos":
				# We may have asked already in a previous iteration.
				if agree_to_tos_url is not None:
					continue

				# Can't ask the user a question in this mode. Warn the user that something
				# needs to be done.
				if headless:
					print(", ".join(request["domains"]) + " need a new or renewed TLS certificate.")
					print()
					print("This box can't do that automatically for you until you agree to Let's Encrypt's")
					print("Terms of Service agreement. Use the Mail-in-a-Box control panel to provision")
					print("certificates for these domains.")
					sys.exit(1)

				print("""
I'm going to provision a TLS certificate (formerly called a SSL certificate)
for you from Let's Encrypt (letsencrypt.org).

TLS certificates are cryptographic keys that ensure communication between
you and this box are secure when getting and sending mail and visiting
websites hosted on this box. Let's Encrypt is a free provider of TLS
certificates.

Please open this document in your web browser:

%s

It is Let's Encrypt's terms of service agreement. If you agree, I can
provision that TLS certificate. If you don't agree, you will have an
opportunity to install your own TLS certificate from the Mail-in-a-Box
control panel.

Do you agree to the agreement? Type Y or N and press <ENTER>: """
				 % request["url"], end='', flush=True)
			
				if sys.stdin.readline().strip().upper() != "Y":
					print("\nYou didn't agree. Quitting.")
					sys.exit(1)

				# Okay, indicate agreement on next iteration.
				agree_to_tos_url = request["url"]

			if request["result"] == "wait":
				# Must wait. We'll record until when. The wait occurs below.
				if wait_until is None:
					wait_until = request["until"]
				else:
					wait_until = max(wait_until, request["until"])
				wait_domains += request["domains"]

			if request["result"] == "error":
				print(", ".join(request["domains"]) + ":")
				print(request["message"])

			if request["result"] == "installed":
				print("A TLS certificate was successfully installed for " + ", ".join(request["domains"]) + ".")

		if wait_until:
			# Wait, then loop.
			import time, datetime
			print()
			print("A TLS certificate was requested for: " + ", ".join(wait_domains) + ".")
			first = True
			while wait_until > datetime.datetime.now():
				if not headless or first:
					print ("We have to wait", int(round((wait_until - datetime.datetime.now()).total_seconds())), "seconds for the certificate to be issued...")
				time.sleep(10)
				first = False

			continue # Loop!

		if agree_to_tos_url:
			# The user agrees to the TOS. Loop to try again by agreeing.
			continue # Loop!

		# Unless we were instructed to wait, or we just agreed to the TOS,
		# we're done for now.
		break

	# And finally show the domains with problems.
	if len(status["problems"]) > 0:
		print("TLS certificates could not be provisoned for:")
		for domain in sort_domains(status["problems"], env):
			print("%s: %s" % (domain, status["problems"][domain]))

# INSTALLING A NEW CERTIFICATE FROM THE CONTROL PANEL

def create_csr(domain, ssl_key, country_code, env):
	return shell("check_output", [
                "openssl", "req", "-new",
                "-key", ssl_key,
                "-sha256",
                "-subj", "/C=%s/ST=/L=/O=/CN=%s" % (country_code, domain)])

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
	if raw: return ret
	return "\n".join(ret)

# VALIDATION OF CERTIFICATES

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

		if ndays <= 10 and warn_if_expiring_soon:
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
