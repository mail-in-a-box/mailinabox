#!/usr/bin/python3
#
# Checks that the upstream DNS has been set correctly and that
# SSL certificates have been signed, etc., and if not tells the user
# what to do next.

__ALL__ = ['check_certificate']

import os, os.path, re, subprocess

import dns.reversename, dns.resolver

from dns_update import get_dns_zones, build_tlsa_record
from web_update import get_web_domains, get_domain_ssl_files
from mailconfig import get_mail_domains, get_mail_aliases

from utils import shell, sort_domains, load_env_vars_from_file

def run_checks(env):
	run_system_checks(env)
	run_domain_checks(env)

def run_system_checks(env):
	print("System")
	print("======")

	# Check that SSH login with password is disabled.
	sshd = open("/etc/ssh/sshd_config").read()
	if re.search("\nPasswordAuthentication\s+yes", sshd) \
		or not re.search("\nPasswordAuthentication\s+no", sshd):
		print_error("""The SSH server on this machine permits password-based login. A more secure
			way to log in is using a public key. Add your SSH public key to $HOME/.ssh/authorized_keys, check
			that you can log in without a password, set the option 'PasswordAuthentication no' in
			/etc/ssh/sshd_config, and then restart the openssh via 'sudo service ssh restart'.""")
	else:
		print_ok("SSH disallows password-based login.")

	# Check that the administrator alias exists since that's where all
	# admin email is automatically directed.
	check_alias_exists("administrator@" + env['PRIMARY_HOSTNAME'], env)

	print()

def run_domain_checks(env):
	# Get the list of domains we handle mail for.
	mail_domains = get_mail_domains(env)

	# Get the list of domains we serve DNS zones for (i.e. does not include subdomains).
	dns_zonefiles = dict(get_dns_zones(env))
	dns_domains = set(dns_zonefiles)

	# Get the list of domains we serve HTTPS for.
	web_domains = set(get_web_domains(env))

	# Check the domains.
	for domain in sort_domains(mail_domains | dns_domains | web_domains, env):
		print(domain)
		print("=" * len(domain))

		if domain == env["PRIMARY_HOSTNAME"]:
			check_primary_hostname_dns(domain, env)
		
		if domain in dns_domains:
			check_dns_zone(domain, env, dns_zonefiles)
		
		if domain in mail_domains:
			check_mail_domain(domain, env)

		if domain in web_domains:
			check_web_domain(domain, env)

		print()

def check_primary_hostname_dns(domain, env):
	# Check that the ns1/ns2 hostnames resolve to A records. This information probably
	# comes from the TLD since the information is set at the registrar.
	ip = query_dns("ns1." + domain, "A") + '/' + query_dns("ns2." + domain, "A")
	if ip == env['PUBLIC_IP'] + '/' + env['PUBLIC_IP']:
		print_ok("Nameserver IPs are correct at registrar. [ns1/ns2.%s => %s]" % (env['PRIMARY_HOSTNAME'], env['PUBLIC_IP']))
	else:
		print_error("""Nameserver IP addresses are incorrect. The ns1.%s and ns2.%s nameservers must be configured at your domain name
			registrar as having the IP address %s. They currently report addresses of %s. It may take several hours for
			public DNS to update after a change."""
			% (env['PRIMARY_HOSTNAME'], env['PRIMARY_HOSTNAME'], env['PUBLIC_IP'], ip))

	# Check that PRIMARY_HOSTNAME resolves to PUBLIC_IP in public DNS.
	ip = query_dns(domain, "A")
	if ip == env['PUBLIC_IP']:
		print_ok("Domain resolves to box's IP address. [%s => %s]" % (env['PRIMARY_HOSTNAME'], env['PUBLIC_IP']))
	else:
		print_error("""This domain must resolve to your box's IP address (%s) in public DNS but it currently resolves
			to %s. It may take several hours for public DNS to update after a change. This problem may result from other
			issues listed here."""
			% (env['PUBLIC_IP'], ip))

	# Check reverse DNS on the PRIMARY_HOSTNAME. Note that it might not be
	# a DNS zone if it is a subdomain of another domain we have a zone for.
	ipaddr_rev = dns.reversename.from_address(env['PUBLIC_IP'])
	existing_rdns = query_dns(ipaddr_rev, "PTR")
	if existing_rdns == domain:
		print_ok("Reverse DNS is set correctly at ISP. [%s => %s]" % (env['PUBLIC_IP'], env['PRIMARY_HOSTNAME']))
	else:
		print_error("""Your box's reverse DNS is currently %s, but it should be %s. Your ISP or cloud provider will have instructions
			on setting up reverse DNS for your box at %s.""" % (existing_rdns, domain, env['PUBLIC_IP']) )

	# Check the TLSA record.
	tlsa_qname = "_25._tcp." + domain
	tlsa25 = query_dns(tlsa_qname, "TLSA", nxdomain=None)
	tlsa25_expected = build_tlsa_record(env)
	if tlsa25 == tlsa25_expected:
		print_ok("""The DANE TLSA record for incoming mail is correct (%s).""" % tlsa_qname,)
	elif tlsa25 is None:
		print_error("""The DANE TLSA record for incoming mail is not set. This is optional.""")
	else:
		print_error("""The DANE TLSA record for incoming mail (%s) is not correct. It is '%s' but it should be '%s'. Try running tools/dns_update to
			regenerate the record. It may take several hours for
                        public DNS to update after a change."""
                        % (tlsa_qname, tlsa25, tlsa25_expected))

	# Check that the hostmaster@ email address exists.
	check_alias_exists("hostmaster@" + domain, env)

def check_alias_exists(alias, env):
	mail_alises = dict(get_mail_aliases(env))
	if alias in mail_alises:
		print_ok("%s exists as a mail alias [=> %s]" % (alias, mail_alises[alias]))
	else:
		print_error("""You must add a mail alias for %s and direct email to you or another administrator.""" % alias)

def check_dns_zone(domain, env, dns_zonefiles):
	# We provide a DNS zone for the domain. It should have NS records set up
	# at the domain name's registrar pointing to this box.
	existing_ns = query_dns(domain, "NS")
	correct_ns = "ns1.BOX; ns2.BOX".replace("BOX", env['PRIMARY_HOSTNAME'])
	if existing_ns == correct_ns:
		print_ok("Nameservers are set correctly at registrar. [%s]" % correct_ns)
	else:
		print_error("""The nameservers set on this domain are incorrect. They are currently %s. Use your domain name registar's
			control panel to set the nameservers to %s."""
				% (existing_ns, correct_ns) )

	# See if the domain has a DS record set at the registrar. The DS record may have
	# several forms. We have to be prepared to check for any valid record. We've
	# pre-generated all of the valid digests --- read them in.
	ds_correct = open('/etc/nsd/zones/' + dns_zonefiles[domain] + '.ds').read().strip().split("\n")
	digests = { }
	for rr_ds in ds_correct:
		ds_keytag, ds_alg, ds_digalg, ds_digest = rr_ds.split("\t")[4].split(" ")
		digests[ds_digalg] = ds_digest

	# Some registrars may want the public key so they can compute the digest. The DS
	# record that we suggest using is for the KSK (and that's how the DS records were generated).
	dnssec_keys = load_env_vars_from_file(os.path.join(env['STORAGE_ROOT'], 'dns/dnssec/keys.conf'))
	dnsssec_pubkey = open(os.path.join(env['STORAGE_ROOT'], 'dns/dnssec/' + dnssec_keys['KSK'] + '.key')).read().split("\t")[3].split(" ")[3]

	# Query public DNS for the DS record at the registrar.
	ds = query_dns(domain, "DS", nxdomain=None)
	ds_looks_valid = ds and len(ds.split(" ")) == 4
	if ds_looks_valid: ds = ds.split(" ")
	if ds_looks_valid and ds[0] == ds_keytag and ds[1] == '7' and ds[3] == digests.get(ds[2]):
		print_ok("DNS 'DS' record is set correctly at registrar.")
	else:
		if ds == None:
			print_error("""This domain's DNS DS record is not set. The DS record is optional. The DS record activates DNSSEC.
				To set a DS record, you must follow the instructions provided by your domain name registrar and provide to them this information:""")
		else:
			print_error("""This domain's DNS DS record is incorrect. The chain of trust is broken between the public DNS system
				and this machine's DNS server. It may take several hours for public DNS to update after a change. If you did not recently
				make a change, you must resolve this immediately by following the instructions provided by your domain name registrar and
				provide to them this information:""")
		print()
		print("\tKey Tag: " + ds_keytag + ("" if not ds_looks_valid or ds[0] == ds_keytag else " (Got '%s')" % ds[0]))
		print("\tKey Flags: KSK")
		print("\tAlgorithm: 7 / RSASHA1-NSEC3-SHA1" + ("" if not ds_looks_valid or ds[1] == '7' else " (Got '%s')" % ds[1]))
		print("\tDigest Type: 2 / SHA-256")
		print("\tDigest: " + digests['2'])
		if ds_looks_valid and ds[3] != digests.get(ds[2]):
			print("\t(Got digest type %s and digest %s which do not match.)" % (ds[2], ds[3]))
		print("\tPublic Key: " + dnsssec_pubkey)
		print()
		print("\tBulk/Record Format:")
		print("\t" + ds_correct[0])
		print("")

def check_mail_domain(domain, env):
	# Check the MX record.

	mx = query_dns(domain, "MX", nxdomain=None)
	expected_mx = "10 " + env['PRIMARY_HOSTNAME']

	if mx == expected_mx:
		print_ok("Domain's email is directed to this domain. [%s => %s]" % (domain, mx))

	elif mx == None:
		# A missing MX record is okay on the primary hostname because
		# the primary hostname's A record (the MX fallback) is... itself,
		# which is what we want the MX to be.
		if domain == env['PRIMARY_HOSTNAME']:
			print_ok("Domain's email is directed to this domain. [%s has no MX record, which is ok]" % (domain,))

		# And a missing MX record is okay on other domains if the A record
		# matches the A record of the PRIMARY_HOSTNAME. Actually this will
		# probably confuse DANE TLSA, but we'll let that slide for now.
		else:
			domain_a = query_dns(domain, "A", nxdomain=None)
			primary_a = query_dns(env['PRIMARY_HOSTNAME'], "A", nxdomain=None)
			if domain_a != None and domain_a == primary_a:
				print_ok("Domain's email is directed to this domain. [%s has no MX record but its A record is OK]" % (domain,))
			else:
				print_error("""This domain's DNS MX record is not set. It should be '%s'. Mail will not
					be delivered to this box. It may take several hours for public DNS to update after a
					change. This problem may result from other issues listed here.""" % (expected_mx,))

	else:
		print_error("""This domain's DNS MX record is incorrect. It is currently set to '%s' but should be '%s'. Mail will not
			be delivered to this box. It may take several hours for public DNS to update after a change. This problem may result from
			other issues listed here.""" % (mx, expected_mx))

	# Check that the postmaster@ email address exists.
	check_alias_exists("postmaster@" + domain, env)

def check_web_domain(domain, env):
	# See if the domain's A record resolves to our PUBLIC_IP. This is already checked
	# for PRIMARY_HOSTNAME, for which it is required for mail specifically. For it and
	# other domains, it is required to access its website.
	if domain != env['PRIMARY_HOSTNAME']:
		ip = query_dns(domain, "A")
		if ip == env['PUBLIC_IP']:
			print_ok("Domain resolves to this box's IP address. [%s => %s]" % (domain, env['PUBLIC_IP']))
		else:
			print_error("""This domain should resolve to your box's IP address (%s) if you would like the box to serve
				webmail or a website on this domain. The domain currently resolves to %s in public DNS. It may take several hours for
				public DNS to update after a change. This problem may result from other issues listed here.""" % (env['PUBLIC_IP'], ip))

	# We need a SSL certificate for PRIMARY_HOSTNAME because that's where the
	# user will log in with IMAP or webmail. Any other domain we serve a
	# website for also needs a signed certificate.
	check_ssl_cert(domain, env)

def query_dns(qname, rtype, nxdomain='[Not Set]'):
	resolver = dns.resolver.get_default_resolver()
	try:
		response = dns.resolver.query(qname, rtype)
	except (dns.resolver.NoNameservers, dns.resolver.NXDOMAIN, dns.resolver.NoAnswer):
		# Host did not have an answer for this query; not sure what the
		# difference is between the two exceptions.
		return nxdomain

	# There may be multiple answers; concatenate the response. Remove trailing
	# periods from responses since that's how qnames are encoded in DNS but is
	# confusing for us.
	return "; ".join(str(r).rstrip('.') for r in response)

def check_ssl_cert(domain, env):
	# Check that SSL certificate is signed.

	# Skip the check if the A record is not pointed here.
	if query_dns(domain, "A") != env['PUBLIC_IP']: return

	# Where is the SSL stored?
	ssl_key, ssl_certificate, ssl_csr_path = get_domain_ssl_files(domain, env)

	if not os.path.exists(ssl_certificate):
		print_error("The SSL certificate file for this domain is missing.")
		return

	# Check that the certificate is good.

	cert_status = check_certificate(domain, ssl_certificate, ssl_key)

	if cert_status == "SELF-SIGNED":
		fingerprint = shell('check_output', [
			"openssl",
			"x509",
			"-in", ssl_certificate,
			"-noout",
			"-fingerprint"
			])
		fingerprint = re.sub(".*Fingerprint=", "", fingerprint).strip()

		if domain == env['PRIMARY_HOSTNAME']:
			print_error("""The SSL certificate for this domain is currently self-signed. You will get a security
			warning when you check or send email and when visiting this domain in a web browser (for webmail or
			static site hosting). You may choose to confirm the security exception, but check that the certificate
			fingerprint matches the following:""")
			print()
			print("   " + fingerprint)
		else:
			print_error("""The SSL certificate for this domain is currently self-signed. Visitors to a website on
			this domain will get a security warning. If you are not serving a website on this domain, then it is
			safe to leave the self-signed certificate in place.""")
		print()
		print_block("""You can purchase a signed certificate from many places. You will need to provide this Certificate Signing Request (CSR)
			to whoever you purchase the SSL certificate from:""")
		print()
		print(open(ssl_csr_path).read().strip())
		print()
		print_block("""When you purchase an SSL certificate you will receive a certificate in PEM format and possibly a file containing intermediate certificates in PEM format.
			If you receive intermediate certificates, use a text editor and paste your certificate on top and then the intermediate certificates
			below it. Save the file and place it onto this machine at %s. Then run "service nginx restart".""" % ssl_certificate)

	elif cert_status == "OK":
		print_ok("SSL certificate is signed & valid.")

	else:
		print_error("The SSL certificate has a problem:")
		print("")
		print(cert_status)
		print("")

def check_certificate(domain, ssl_certificate, ssl_private_key):
	# Use openssl verify to check the status of a certificate.

	# First check that the certificate is for the right domain. The domain
	# must be found in the Subject Common Name (CN) or be one of the
	# Subject Alternative Names.
	cert_dump = shell('check_output', [
		"openssl", "x509",
		"-in", ssl_certificate,
		"-noout", "-text", "-nameopt", "rfc2253",
		])
	cert_dump = cert_dump.split("\n")
	certificate_names = set()
	while len(cert_dump) > 0:
		line = cert_dump.pop(0)

		# Grab from the Subject Common Name. We include the indentation
		# at the start of the line in case maybe the cert includes the
		# common name of some other referenced entity (which would be
		# indented, I hope).
		m = re.match("        Subject: CN=([^,]+)", line)
		if m:
			certificate_names.add(m.group(1))
	
		# Grab from the Subject Alternative Name, which is a comma-delim
		# list of names, like DNS:mydomain.com, DNS:otherdomain.com.
		m = re.match("            X509v3 Subject Alternative Name:", line)
		if m:
			names = re.split(",\s*", cert_dump.pop(0).strip())
			for n in names:
				m = re.match("DNS:(.*)", n)
				if m:
					certificate_names.add(m.group(1))

	if domain is not None and domain not in certificate_names:
		return "This certificate is for the wrong domain names. It is for %s." % \
			", ".join(sorted(certificate_names))

	# Second, check that the certificate matches the private key. Get the modulus of the
	# private key and of the public key in the certificate. They should match. The output
	# of each command looks like "Modulus=XXXXX".
	if ssl_private_key is not None:
		private_key_modulus = shell('check_output', [
			"openssl", "rsa",
			"-inform", "PEM",
			"-noout", "-modulus",
			"-in", ssl_private_key])
		cert_key_modulus = shell('check_output', [
			"openssl", "x509",
			"-in", ssl_certificate,
			"-noout", "-modulus"])
		if private_key_modulus != cert_key_modulus:
			return "The certificate installed at %s does not correspond to the private key at %s." % (ssl_certificate, ssl_private_key)

	# Next validate that the certificate is valid. This checks whether the certificate
	# is self-signed, that the chain of trust makes sense, that it is signed by a CA
	# that Ubuntu has installed on this machine's list of CAs, and I think that it hasn't
	# expired.

	# In order to verify with openssl, we need to split out any
	# intermediary certificates in the chain (if any) from our
	# certificate (at the top). They need to be passed separately.

	cert = open(ssl_certificate).read()
	m = re.match(r'(-*BEGIN CERTIFICATE-*.*?-*END CERTIFICATE-*)(.*)', cert, re.S)
	if m == None:
		return "The certificate file is an invalid PEM certificate."
	mycert, chaincerts = m.groups()

	# This command returns a non-zero exit status in most cases, so trap errors.

	retcode, verifyoutput = shell('check_output', [
		"openssl",
		"verify", "-verbose",
		"-purpose", "sslserver", "-policy_check",]
		+ ([] if chaincerts.strip() == "" else ["-untrusted", "/dev/stdin"])
		+ [ssl_certificate],
		input=chaincerts.encode('ascii'),
		trap=True)

	if "self signed" in verifyoutput:
		# Certificate is self-signed.
		return "SELF-SIGNED"
	elif retcode == 0:
		# Certificate is OK.
		return "OK"
	else:
		return verifyoutput.strip()

def print_ok(message):
	print_block(message, first_line="✓  ")

def print_error(message):
	print_block(message, first_line="✖  ")

try:
	terminal_columns = int(shell('check_output', ['stty', 'size']).split()[1])
except:
	terminal_columns = 76
def print_block(message, first_line="   "):
	print(first_line, end='')
	message = re.sub("\n\s*", " ", message)
	words = re.split("(\s+)", message)
	linelen = 0
	for w in words:
		if linelen + len(w) > terminal_columns-1-len(first_line):
			print()
			print("   ", end="")
			linelen = 0
		if linelen == 0 and w.strip() == "": continue
		print(w, end="")
		linelen += len(w)
	if linelen > 0:
		print()

if __name__ == "__main__":
	from utils import load_environment
	run_checks(load_environment())
