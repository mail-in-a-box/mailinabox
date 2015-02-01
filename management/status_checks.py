#!/usr/bin/python3
#
# Checks that the upstream DNS has been set correctly and that
# SSL certificates have been signed, etc., and if not tells the user
# what to do next.

__ALL__ = ['check_certificate']

import os, os.path, re, subprocess, datetime, multiprocessing.pool

import dns.reversename, dns.resolver
import dateutil.parser, dateutil.tz

from dns_update import get_dns_zones, build_tlsa_record, get_custom_dns_config
from web_update import get_web_domains, get_domain_ssl_files
from mailconfig import get_mail_domains, get_mail_aliases

from utils import shell, sort_domains, load_env_vars_from_file

def run_checks(env, output):
	# run systems checks
	output.add_heading("System")

	# check that services are running
	if not run_services_checks(env, output):
		# If critical services are not running, stop. If bind9 isn't running,
		# all later DNS checks will timeout and that will take forever to
		# go through, and if running over the web will cause a fastcgi timeout.
		return

	# clear bind9's DNS cache so our DNS checks are up to date
	# (ignore errors; if bind9/rndc isn't running we'd already report
	# that in run_services checks.)
	shell('check_call', ["/usr/sbin/rndc", "flush"], trap=True)

	run_system_checks(env, output)

	# perform other checks asynchronously

	pool = multiprocessing.pool.Pool(processes=1)
	r1 = pool.apply_async(run_network_checks, [env])
	r2 = run_domain_checks(env)
	r1.get().playback(output)
	r2.playback(output)

def get_ssh_port():
    # Returns ssh port
    output = shell('check_output', ['sshd', '-T'])
    returnNext = False

    for e in output.split():
        if returnNext:
            return int(e)
        if e == "port":
            returnNext = True

def run_services_checks(env, output):
	# Check that system services are running.

	services = [
		{ "name": "Local DNS (bind9)", "port": 53, "public": False, },
		#{ "name": "NSD Control", "port": 8952, "public": False, },
		{ "name": "Local DNS Control (bind9/rndc)", "port": 953, "public": False, },
		{ "name": "Dovecot LMTP LDA", "port": 10026, "public": False, },
		{ "name": "Postgrey", "port": 10023, "public": False, },
		{ "name": "Spamassassin", "port": 10025, "public": False, },
		{ "name": "OpenDKIM", "port": 8891, "public": False, },
		{ "name": "Memcached", "port": 11211, "public": False, },
		{ "name": "Sieve (dovecot)", "port": 4190, "public": True, },
		{ "name": "Mail-in-a-Box Management Daemon", "port": 10222, "public": False, },

		{ "name": "SSH Login (ssh)", "port": get_ssh_port(), "public": True, },
		{ "name": "Public DNS (nsd4)", "port": 53, "public": True, },
		{ "name": "Incoming Mail (SMTP/postfix)", "port": 25, "public": True, },
		{ "name": "Outgoing Mail (SMTP 587/postfix)", "port": 587, "public": True, },
		#{ "name": "Postfix/master", "port": 10587, "public": True, },
		{ "name": "IMAPS (dovecot)", "port": 993, "public": True, },
		{ "name": "HTTP Web (nginx)", "port": 80, "public": True, },
		{ "name": "HTTPS Web (nginx)", "port": 443, "public": True, },
	]

	all_running = True
	fatal = False
	pool = multiprocessing.pool.Pool(processes=10)
	ret = pool.starmap(check_service, ((i, service, env) for i, service in enumerate(services)), chunksize=1)
	for i, running, fatal2, output2 in sorted(ret):
		all_running = all_running and running
		fatal = fatal or fatal2
		output2.playback(output)

	if all_running:
		output.print_ok("All system services are running.")

	return not fatal

def check_service(i, service, env):
	import socket
	output = BufferedOutput()
	running = False
	fatal = False
	s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
	s.settimeout(1)
	try:
		s.connect((
			"127.0.0.1" if not service["public"] else env['PUBLIC_IP'],
			service["port"]))
		running = True

	except OSError as e:
		if service['name'] == 'SSH Login (ssh)':
			output.print_error("%s is not running (%s). (Should be running on port %s)" % (service['name'], str(e), str(get_ssh_port())))
		else:
			output.print_error("%s is not running (%s)." % (service['name'], str(e)))

		# Why is nginx not running?
		if service["port"] in (80, 443):
			output.print_line(shell('check_output', ['nginx', '-t'], capture_stderr=True, trap=True)[1].strip())

		# Flag if local DNS is not running.
		if service["port"] == 53 and service["public"] == False:
			fatal = True
	finally:
		s.close()

	return (i, running, fatal, output)

def run_system_checks(env, output):
	check_ssh_password(env, output)
	check_software_updates(env, output)
	check_system_aliases(env, output)
	check_free_disk_space(env, output)

def check_ssh_password(env, output):
	# Check that SSH login with password is disabled. The openssh-server
	# package may not be installed so check that before trying to access
	# the configuration file.
	if not os.path.exists("/etc/ssh/sshd_config"):
		return
	sshd = open("/etc/ssh/sshd_config").read()
	if re.search("\nPasswordAuthentication\s+yes", sshd) \
		or not re.search("\nPasswordAuthentication\s+no", sshd):
		output.print_error("""The SSH server on this machine permits password-based login. A more secure
			way to log in is using a public key. Add your SSH public key to $HOME/.ssh/authorized_keys, check
			that you can log in without a password, set the option 'PasswordAuthentication no' in
			/etc/ssh/sshd_config, and then restart the openssh via 'sudo service ssh restart'.""")
	else:
		output.print_ok("SSH disallows password-based login.")

def check_software_updates(env, output):
	# Check for any software package updates.
	pkgs = list_apt_updates(apt_update=False)
	if os.path.exists("/var/run/reboot-required"):
		output.print_error("System updates have been installed and a reboot of the machine is required.")
	elif len(pkgs) == 0:
		output.print_ok("System software is up to date.")
	else:
		output.print_error("There are %d software packages that can be updated." % len(pkgs))
		for p in pkgs:
			output.print_line("%s (%s)" % (p["package"], p["version"]))

def check_system_aliases(env, output):
	# Check that the administrator alias exists since that's where all
	# admin email is automatically directed.
	check_alias_exists("administrator@" + env['PRIMARY_HOSTNAME'], env, output)

def check_free_disk_space(env, output):
	# Check free disk space.
	st = os.statvfs(env['STORAGE_ROOT'])
	bytes_total = st.f_blocks * st.f_frsize
	bytes_free = st.f_bavail * st.f_frsize
	disk_msg = "The disk has %s GB space remaining." % str(round(bytes_free/1024.0/1024.0/1024.0*10.0)/10.0)
	if bytes_free > .3 * bytes_total:
		output.print_ok(disk_msg)
	elif bytes_free > .15 * bytes_total:
		output.print_warning(disk_msg)
	else:
		output.print_error(disk_msg)

def run_network_checks(env):
	# Also see setup/network-checks.sh.

	output = BufferedOutput()
	output.add_heading("Network")

	# Stop if we cannot make an outbound connection on port 25. Many residential
	# networks block outbound port 25 to prevent their network from sending spam.
	# See if we can reach one of Google's MTAs with a 5-second timeout.
	code, ret = shell("check_call", ["/bin/nc", "-z", "-w5", "aspmx.l.google.com", "25"], trap=True)
	if ret == 0:
		output.print_ok("Outbound mail (SMTP port 25) is not blocked.")
	else:
		output.print_error("""Outbound mail (SMTP port 25) seems to be blocked by your network. You
			will not be able to send any mail. Many residential networks block port 25 to prevent hijacked
			machines from being able to send spam. A quick connection test to Google's mail server on port 25
			failed.""")

	# Stop if the IPv4 address is listed in the ZEN Spamhaus Block List.
	# The user might have ended up on an IP address that was previously in use
	# by a spammer, or the user may be deploying on a residential network. We
	# will not be able to reliably send mail in these cases.
	rev_ip4 = ".".join(reversed(env['PUBLIC_IP'].split('.')))
	zen = query_dns(rev_ip4+'.zen.spamhaus.org', 'A', nxdomain=None)
	if zen is None:
		output.print_ok("IP address is not blacklisted by zen.spamhaus.org.")
	else:
		output.print_error("""The IP address of this machine %s is listed in the Spamhaus Block List (code %s),
			which may prevent recipients from receiving your email. See http://www.spamhaus.org/query/ip/%s."""
			% (env['PUBLIC_IP'], zen, env['PUBLIC_IP']))

	return output

def run_domain_checks(env):
	# Get the list of domains we handle mail for.
	mail_domains = get_mail_domains(env)

	# Get the list of domains we serve DNS zones for (i.e. does not include subdomains).
	dns_zonefiles = dict(get_dns_zones(env))
	dns_domains = set(dns_zonefiles)

	# Get the list of domains we serve HTTPS for.
	web_domains = set(get_web_domains(env))

	domains_to_check = mail_domains | dns_domains | web_domains

	# Serial version:
	#for domain in sort_domains(domains_to_check, env):
	#	run_domain_checks_on_domain(domain, env, dns_domains, dns_zonefiles, mail_domains, web_domains)

	# Parallelize the checks across a worker pool.
	args = ((domain, env, dns_domains, dns_zonefiles, mail_domains, web_domains)
		for domain in domains_to_check)
	pool = multiprocessing.pool.Pool(processes=10)
	ret = pool.starmap(run_domain_checks_on_domain, args, chunksize=1)
	ret = dict(ret) # (domain, output) => { domain: output }
	output = BufferedOutput()
	for domain in sort_domains(ret, env):
		ret[domain].playback(output)
	return output

def run_domain_checks_on_domain(domain, env, dns_domains, dns_zonefiles, mail_domains, web_domains):
	output = BufferedOutput()

	output.add_heading(domain)

	if domain == env["PRIMARY_HOSTNAME"]:
		check_primary_hostname_dns(domain, env, output, dns_domains, dns_zonefiles)

	if domain in dns_domains:
		check_dns_zone(domain, env, output, dns_zonefiles)

	if domain in mail_domains:
		check_mail_domain(domain, env, output)

	if domain in web_domains:
		check_web_domain(domain, env, output)

	if domain in dns_domains:
		check_dns_zone_suggestions(domain, env, output, dns_zonefiles)

	return (domain, output)

def check_primary_hostname_dns(domain, env, output, dns_domains, dns_zonefiles):
	# If a DS record is set on the zone containing this domain, check DNSSEC now.
	for zone in dns_domains:
		if zone == domain or domain.endswith("." + zone):
			if query_dns(zone, "DS", nxdomain=None) is not None:
				check_dnssec(zone, env, output, dns_zonefiles, is_checking_primary=True)

	# Check that the ns1/ns2 hostnames resolve to A records. This information probably
	# comes from the TLD since the information is set at the registrar as glue records.
	# We're probably not actually checking that here but instead checking that we, as
	# the nameserver, are reporting the right info --- but if the glue is incorrect this
	# will probably fail.
	ip = query_dns("ns1." + domain, "A") + '/' + query_dns("ns2." + domain, "A")
	if ip == env['PUBLIC_IP'] + '/' + env['PUBLIC_IP']:
		output.print_ok("Nameserver glue records are correct at registrar. [ns1/ns2.%s => %s]" % (env['PRIMARY_HOSTNAME'], env['PUBLIC_IP']))
	else:
		output.print_error("""Nameserver glue records are incorrect. The ns1.%s and ns2.%s nameservers must be configured at your domain name
			registrar as having the IP address %s. They currently report addresses of %s. It may take several hours for
			public DNS to update after a change."""
			% (env['PRIMARY_HOSTNAME'], env['PRIMARY_HOSTNAME'], env['PUBLIC_IP'], ip))

	# Check that PRIMARY_HOSTNAME resolves to PUBLIC_IP in public DNS.
	ip = query_dns(domain, "A")
	if ip == env['PUBLIC_IP']:
		output.print_ok("Domain resolves to box's IP address. [%s => %s]" % (env['PRIMARY_HOSTNAME'], env['PUBLIC_IP']))
	else:
		output.print_error("""This domain must resolve to your box's IP address (%s) in public DNS but it currently resolves
			to %s. It may take several hours for public DNS to update after a change. This problem may result from other
			issues listed here."""
			% (env['PUBLIC_IP'], ip))

	# Check reverse DNS on the PRIMARY_HOSTNAME. Note that it might not be
	# a DNS zone if it is a subdomain of another domain we have a zone for.
	ipaddr_rev = dns.reversename.from_address(env['PUBLIC_IP'])
	existing_rdns = query_dns(ipaddr_rev, "PTR")
	if existing_rdns == domain:
		output.print_ok("Reverse DNS is set correctly at ISP. [%s => %s]" % (env['PUBLIC_IP'], env['PRIMARY_HOSTNAME']))
	else:
		output.print_error("""Your box's reverse DNS is currently %s, but it should be %s. Your ISP or cloud provider will have instructions
			on setting up reverse DNS for your box at %s.""" % (existing_rdns, domain, env['PUBLIC_IP']) )

	# Check the TLSA record.
	tlsa_qname = "_25._tcp." + domain
	tlsa25 = query_dns(tlsa_qname, "TLSA", nxdomain=None)
	tlsa25_expected = build_tlsa_record(env)
	if tlsa25 == tlsa25_expected:
		output.print_ok("""The DANE TLSA record for incoming mail is correct (%s).""" % tlsa_qname,)
	elif tlsa25 is None:
		output.print_error("""The DANE TLSA record for incoming mail is not set. This is optional.""")
	else:
		output.print_error("""The DANE TLSA record for incoming mail (%s) is not correct. It is '%s' but it should be '%s'.
			It may take several hours for public DNS to update after a change."""
                        % (tlsa_qname, tlsa25, tlsa25_expected))

	# Check that the hostmaster@ email address exists.
	check_alias_exists("hostmaster@" + domain, env, output)

def check_alias_exists(alias, env, output):
	mail_alises = dict(get_mail_aliases(env))
	if alias in mail_alises:
		output.print_ok("%s exists as a mail alias [=> %s]" % (alias, mail_alises[alias]))
	else:
		output.print_error("""You must add a mail alias for %s and direct email to you or another administrator.""" % alias)

def check_dns_zone(domain, env, output, dns_zonefiles):
	# If a DS record is set at the registrar, check DNSSEC first because it will affect the NS query.
	# If it is not set, we suggest it last.
	if query_dns(domain, "DS", nxdomain=None) is not None:
		check_dnssec(domain, env, output, dns_zonefiles)

	# We provide a DNS zone for the domain. It should have NS records set up
	# at the domain name's registrar pointing to this box. The secondary DNS
	# server may be customized. Unfortunately this may not check the domain's
	# whois information -- we may be getting the NS records from us rather than
	# the TLD, and so we're not actually checking the TLD. For that we'd need
	# to do a DNS trace.
	custom_dns = get_custom_dns_config(env)
	existing_ns = query_dns(domain, "NS")
	correct_ns = "; ".join(sorted([
		"ns1." + env['PRIMARY_HOSTNAME'],
		custom_dns.get("_secondary_nameserver", "ns2." + env['PRIMARY_HOSTNAME']),
		]))
	if existing_ns.lower() == correct_ns.lower():
		output.print_ok("Nameservers are set correctly at registrar. [%s]" % correct_ns)
	else:
		output.print_error("""The nameservers set on this domain are incorrect. They are currently %s. Use your domain name registrar's
			control panel to set the nameservers to %s."""
				% (existing_ns, correct_ns) )

def check_dns_zone_suggestions(domain, env, output, dns_zonefiles):
	# Since DNSSEC is optional, if a DS record is NOT set at the registrar suggest it.
	# (If it was set, we did the check earlier.)
	if query_dns(domain, "DS", nxdomain=None) is None:
		check_dnssec(domain, env, output, dns_zonefiles)


def check_dnssec(domain, env, output, dns_zonefiles, is_checking_primary=False):
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
	alg_name_map = { '7': 'RSASHA1-NSEC3-SHA1', '8': 'RSASHA256' }
	dnssec_keys = load_env_vars_from_file(os.path.join(env['STORAGE_ROOT'], 'dns/dnssec/%s.conf' % alg_name_map[ds_alg]))
	dnsssec_pubkey = open(os.path.join(env['STORAGE_ROOT'], 'dns/dnssec/' + dnssec_keys['KSK'] + '.key')).read().split("\t")[3].split(" ")[3]

	# Query public DNS for the DS record at the registrar.
	ds = query_dns(domain, "DS", nxdomain=None)
	ds_looks_valid = ds and len(ds.split(" ")) == 4
	if ds_looks_valid: ds = ds.split(" ")
	if ds_looks_valid and ds[0] == ds_keytag and ds[1] == ds_alg and ds[3] == digests.get(ds[2]):
		if is_checking_primary: return
		output.print_ok("DNSSEC 'DS' record is set correctly at registrar.")
	else:
		if ds == None:
			if is_checking_primary: return
			output.print_error("""This domain's DNSSEC DS record is not set. The DS record is optional. The DS record activates DNSSEC.
				To set a DS record, you must follow the instructions provided by your domain name registrar and provide to them this information:""")
		else:
			if is_checking_primary:
				output.print_error("""The DNSSEC 'DS' record for %s is incorrect. See further details below.""" % domain)
				return
			output.print_error("""This domain's DNSSEC DS record is incorrect. The chain of trust is broken between the public DNS system
				and this machine's DNS server. It may take several hours for public DNS to update after a change. If you did not recently
				make a change, you must resolve this immediately by following the instructions provided by your domain name registrar and
				provide to them this information:""")
		output.print_line("")
		output.print_line("Key Tag: " + ds_keytag + ("" if not ds_looks_valid or ds[0] == ds_keytag else " (Got '%s')" % ds[0]))
		output.print_line("Key Flags: KSK")
		output.print_line(
			  ("Algorithm: %s / %s" % (ds_alg, alg_name_map[ds_alg]))
			+ ("" if not ds_looks_valid or ds[1] == ds_alg else " (Got '%s')" % ds[1]))
			# see http://www.iana.org/assignments/dns-sec-alg-numbers/dns-sec-alg-numbers.xhtml
		output.print_line("Digest Type: 2 / SHA-256")
			# http://www.ietf.org/assignments/ds-rr-types/ds-rr-types.xml
		output.print_line("Digest: " + digests['2'])
		if ds_looks_valid and ds[3] != digests.get(ds[2]):
			output.print_line("(Got digest type %s and digest %s which do not match.)" % (ds[2], ds[3]))
		output.print_line("Public Key: ")
		output.print_line(dnsssec_pubkey, monospace=True)
		output.print_line("")
		output.print_line("Bulk/Record Format:")
		output.print_line("" + ds_correct[0])
		output.print_line("")

def check_mail_domain(domain, env, output):
	# Check the MX record.

	mx = query_dns(domain, "MX", nxdomain=None)
	expected_mx = "10 " + env['PRIMARY_HOSTNAME']

	if mx == expected_mx:
		output.print_ok("Domain's email is directed to this domain. [%s => %s]" % (domain, mx))

	elif mx == None:
		# A missing MX record is okay on the primary hostname because
		# the primary hostname's A record (the MX fallback) is... itself,
		# which is what we want the MX to be.
		if domain == env['PRIMARY_HOSTNAME']:
			output.print_ok("Domain's email is directed to this domain. [%s has no MX record, which is ok]" % (domain,))

		# And a missing MX record is okay on other domains if the A record
		# matches the A record of the PRIMARY_HOSTNAME. Actually this will
		# probably confuse DANE TLSA, but we'll let that slide for now.
		else:
			domain_a = query_dns(domain, "A", nxdomain=None)
			primary_a = query_dns(env['PRIMARY_HOSTNAME'], "A", nxdomain=None)
			if domain_a != None and domain_a == primary_a:
				output.print_ok("Domain's email is directed to this domain. [%s has no MX record but its A record is OK]" % (domain,))
			else:
				output.print_error("""This domain's DNS MX record is not set. It should be '%s'. Mail will not
					be delivered to this box. It may take several hours for public DNS to update after a
					change. This problem may result from other issues listed here.""" % (expected_mx,))

	else:
		output.print_error("""This domain's DNS MX record is incorrect. It is currently set to '%s' but should be '%s'. Mail will not
			be delivered to this box. It may take several hours for public DNS to update after a change. This problem may result from
			other issues listed here.""" % (mx, expected_mx))

	# Check that the postmaster@ email address exists.
	check_alias_exists("postmaster@" + domain, env, output)

	# Stop if the domain is listed in the Spamhaus Domain Block List.
	# The user might have chosen a domain that was previously in use by a spammer
	# and will not be able to reliably send mail.
	dbl = query_dns(domain+'.dbl.spamhaus.org', "A", nxdomain=None)
	if dbl is None:
		output.print_ok("Domain is not blacklisted by dbl.spamhaus.org.")
	else:
		output.print_error("""This domain is listed in the Spamhaus Domain Block List (code %s),
			which may prevent recipients from receiving your mail.
			See http://www.spamhaus.org/dbl/ and http://www.spamhaus.org/query/domain/%s.""" % (dbl, domain))

def check_web_domain(domain, env, output):
	# See if the domain's A record resolves to our PUBLIC_IP. This is already checked
	# for PRIMARY_HOSTNAME, for which it is required for mail specifically. For it and
	# other domains, it is required to access its website.
	if domain != env['PRIMARY_HOSTNAME']:
		ip = query_dns(domain, "A")
		if ip == env['PUBLIC_IP']:
			output.print_ok("Domain resolves to this box's IP address. [%s => %s]" % (domain, env['PUBLIC_IP']))
		else:
			output.print_error("""This domain should resolve to your box's IP address (%s) if you would like the box to serve
				webmail or a website on this domain. The domain currently resolves to %s in public DNS. It may take several hours for
				public DNS to update after a change. This problem may result from other issues listed here.""" % (env['PUBLIC_IP'], ip))

	# We need a SSL certificate for PRIMARY_HOSTNAME because that's where the
	# user will log in with IMAP or webmail. Any other domain we serve a
	# website for also needs a signed certificate.
	check_ssl_cert(domain, env, output)

def query_dns(qname, rtype, nxdomain='[Not Set]'):
	# Make the qname absolute by appending a period. Without this, dns.resolver.query
	# will fall back a failed lookup to a second query with this machine's hostname
	# appended. This has been causing some false-positive Spamhaus reports. The
	# reverse DNS lookup will pass a dns.name.Name instance which is already
	# absolute so we should not modify that.
	if isinstance(qname, str):
		qname += "."

	# Do the query.
	try:
		response = dns.resolver.query(qname, rtype)
	except (dns.resolver.NoNameservers, dns.resolver.NXDOMAIN, dns.resolver.NoAnswer):
		# Host did not have an answer for this query; not sure what the
		# difference is between the two exceptions.
		return nxdomain
	except dns.exception.Timeout:
		return "[timeout]"

	# There may be multiple answers; concatenate the response. Remove trailing
	# periods from responses since that's how qnames are encoded in DNS but is
	# confusing for us. The order of the answers doesn't matter, so sort so we
	# can compare to a well known order.
	return "; ".join(sorted(str(r).rstrip('.') for r in response))

def check_ssl_cert(domain, env, output):
	# Check that SSL certificate is signed.

	# Skip the check if the A record is not pointed here.
	if query_dns(domain, "A", None) not in (env['PUBLIC_IP'], None): return

	# Where is the SSL stored?
	ssl_key, ssl_certificate = get_domain_ssl_files(domain, env)

	if not os.path.exists(ssl_certificate):
		output.print_error("The SSL certificate file for this domain is missing.")
		return

	# Check that the certificate is good.

	cert_status, cert_status_details = check_certificate(domain, ssl_certificate, ssl_key)

	if cert_status == "OK":
		# The certificate is ok. The details has expiry info.
		output.print_ok("SSL certificate is signed & valid. " + cert_status_details)

	elif cert_status == "SELF-SIGNED":
		# Offer instructions for purchasing a signed certificate.

		fingerprint = shell('check_output', [
			"openssl",
			"x509",
			"-in", ssl_certificate,
			"-noout",
			"-fingerprint"
			])
		fingerprint = re.sub(".*Fingerprint=", "", fingerprint).strip()

		if domain == env['PRIMARY_HOSTNAME']:
			output.print_error("""The SSL certificate for this domain is currently self-signed. You will get a security
			warning when you check or send email and when visiting this domain in a web browser (for webmail or
			static site hosting). Use the SSL Certificates page in this control panel to install a signed SSL certificate.
			You may choose to leave the self-signed certificate in place and confirm the security exception, but check that
			the certificate fingerprint matches the following:""")
			output.print_line("")
			output.print_line("   " + fingerprint, monospace=True)
		else:
			output.print_warning("""The SSL certificate for this domain is currently self-signed. Visitors to a website on
			this domain will get a security warning. If you are not serving a website on this domain, then it is
			safe to leave the self-signed certificate in place. Use the SSL Certificates page in this control panel to
			install a signed SSL certificate.""")

	else:
		output.print_error("The SSL certificate has a problem: " + cert_status)
		if cert_status_details:
			output.print_line("")
			output.print_line(cert_status_details)
			output.print_line("")

def check_certificate(domain, ssl_certificate, ssl_private_key):
	# Use openssl verify to check the status of a certificate.

	# First check that the certificate is for the right domain. The domain
	# must be found in the Subject Common Name (CN) or be one of the
	# Subject Alternative Names. A wildcard might also appear as the CN
	# or in the SAN list, so check for that tool.
	retcode, cert_dump = shell('check_output', [
		"openssl", "x509",
		"-in", ssl_certificate,
		"-noout", "-text", "-nameopt", "rfc2253",
		], trap=True)

	# If the certificate is catastrophically bad, catch that now and report it.
	# More information was probably written to stderr (which we aren't capturing),
	# but it is probably not helpful to the user anyway.
	if retcode != 0:
		return ("The SSL certificate appears to be corrupted or not a PEM-formatted SSL certificate file. (%s)" % ssl_certificate, None)

	cert_dump = cert_dump.split("\n")
	certificate_names = set()
	cert_expiration_date = None
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

		m = re.match("            Not After : (.*)", line)
		if m:
			cert_expiration_date = dateutil.parser.parse(m.group(1))

	domain = domain.encode("idna").decode("ascii")
	wildcard_domain = re.sub("^[^\.]+", "*", domain)
	if domain is not None and domain not in certificate_names and wildcard_domain not in certificate_names:
		return ("The certificate is for the wrong domain name. It is for %s."
			% ", ".join(sorted(certificate_names)), None)

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
			return ("The certificate installed at %s does not correspond to the private key at %s." % (ssl_certificate, ssl_private_key), None)

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
		return ("The certificate file is an invalid PEM certificate.", None)
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
		now = datetime.datetime.now(dateutil.tz.tzlocal())
		ndays = (cert_expiration_date-now).days
		expiry_info = "The certificate expires in %d days on %s." % (ndays, cert_expiration_date.strftime("%x"))
		if ndays <= 31:
			return ("The certificate is expiring soon: " + expiry_info, None)

		# Return the special OK code.
		return ("OK", expiry_info)

_apt_updates = None
def list_apt_updates(apt_update=True):
	# See if we have this information cached recently.
	# Keep the information for 8 hours.
	global _apt_updates
	if _apt_updates is not None and _apt_updates[0] > datetime.datetime.now() - datetime.timedelta(hours=8):
		return _apt_updates[1]

	# Run apt-get update to refresh package list. This should be running daily
	# anyway, so on the status checks page don't do this because it is slow.
	if apt_update:
		shell("check_call", ["/usr/bin/apt-get", "-qq", "update"])

	# Run apt-get upgrade in simulate mode to get a list of what
	# it would do.
	simulated_install = shell("check_output", ["/usr/bin/apt-get", "-qq", "-s", "upgrade"])
	pkgs = []
	for line in simulated_install.split('\n'):
		if line.strip() == "":
			continue
		if re.match(r'^Conf .*', line):
			 # remove these lines, not informative
			continue
		m = re.match(r'^Inst (.*) \[(.*)\] \((\S*)', line)
		if m:
			pkgs.append({ "package": m.group(1), "version": m.group(3), "current_version": m.group(2) })
		else:
			pkgs.append({ "package": "[" + line + "]", "version": "", "current_version": "" })

	# Cache for future requests.
	_apt_updates = (datetime.datetime.now(), pkgs)

	return pkgs


class ConsoleOutput:
	try:
		terminal_columns = int(shell('check_output', ['stty', 'size']).split()[1])
	except:
		terminal_columns = 76

	def add_heading(self, heading):
		print()
		print(heading)
		print("=" * len(heading))

	def print_ok(self, message):
		self.print_block(message, first_line="✓  ")

	def print_error(self, message):
		self.print_block(message, first_line="✖  ")

	def print_warning(self, message):
		self.print_block(message, first_line="?  ")

	def print_block(self, message, first_line="   "):
		print(first_line, end='')
		message = re.sub("\n\s*", " ", message)
		words = re.split("(\s+)", message)
		linelen = 0
		for w in words:
			if linelen + len(w) > self.terminal_columns-1-len(first_line):
				print()
				print("   ", end="")
				linelen = 0
			if linelen == 0 and w.strip() == "": continue
			print(w, end="")
			linelen += len(w)
		print()

	def print_line(self, message, monospace=False):
		for line in message.split("\n"):
			self.print_block(line)

class BufferedOutput:
	# Record all of the instance method calls so we can play them back later.
	def __init__(self):
		self.buf = []
	def __getattr__(self, attr):
		if attr not in ("add_heading", "print_ok", "print_error", "print_warning", "print_block", "print_line"):
			raise AttributeError
		# Return a function that just records the call & arguments to our buffer.
		def w(*args, **kwargs):
			self.buf.append((attr, args, kwargs))
		return w
	def playback(self, output):
		for attr, args, kwargs in self.buf:
			getattr(output, attr)(*args, **kwargs)

if __name__ == "__main__":
	import sys
	from utils import load_environment
	env = load_environment()
	if len(sys.argv) == 1:
		run_checks(env, ConsoleOutput())
	elif sys.argv[1] == "--check-primary-hostname":
		# See if the primary hostname appears resolvable and has a signed certificate.
		domain = env['PRIMARY_HOSTNAME']
		if query_dns(domain, "A") != env['PUBLIC_IP']:
			sys.exit(1)
		ssl_key, ssl_certificate = get_domain_ssl_files(domain, env)
		if not os.path.exists(ssl_certificate):
			sys.exit(1)
		cert_status, cert_status_details = check_certificate(domain, ssl_certificate, ssl_key)
		if cert_status != "OK":
			sys.exit(1)
		sys.exit(0)
