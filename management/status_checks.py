#!/usr/bin/python3
#
# Checks that the upstream DNS has been set correctly and that
# SSL certificates have been signed, etc., and if not tells the user
# what to do next.

import sys, os, os.path, re, subprocess, datetime, multiprocessing.pool

import dns.reversename, dns.resolver
import dateutil.parser, dateutil.tz
import idna

from dns_update import get_dns_zones, build_tlsa_record, get_custom_dns_config, get_secondary_dns, get_custom_dns_record
from web_update import get_web_domains, get_domains_with_a_records
from ssl_certificates import get_ssl_certificates, get_domain_ssl_files, check_certificate
from mailconfig import get_mail_domains, get_mail_aliases

from utils import shell, sort_domains, load_env_vars_from_file, load_settings

def run_checks(rounded_values, env, output, pool):
	# run systems checks
	output.add_heading("System")

	# check that services are running
	if not run_services_checks(env, output, pool):
		# If critical services are not running, stop. If bind9 isn't running,
		# all later DNS checks will timeout and that will take forever to
		# go through, and if running over the web will cause a fastcgi timeout.
		return

	# clear bind9's DNS cache so our DNS checks are up to date
	# (ignore errors; if bind9/rndc isn't running we'd already report
	# that in run_services checks.)
	shell('check_call', ["/usr/sbin/rndc", "flush"], trap=True)

	run_system_checks(rounded_values, env, output)

	# perform other checks asynchronously

	run_network_checks(env, output)
	run_domain_checks(rounded_values, env, output, pool)

def get_ssh_port():
	# Returns ssh port
	try:
		output = shell('check_output', ['sshd', '-T'])
	except FileNotFoundError:
		# sshd is not installed. That's ok.
		return None

	returnNext = False
	for e in output.split():
		if returnNext:
			return int(e)
		if e == "port":
			returnNext = True

	# Did not find port!
	return None

def run_services_checks(env, output, pool):
	# Check that system services are running.

	services = [
		{ "name": "Local DNS (bind9)", "port": 53, "public": False, },
		#{ "name": "NSD Control", "port": 8952, "public": False, },
		{ "name": "Local DNS Control (bind9/rndc)", "port": 953, "public": False, },
		{ "name": "Dovecot LMTP LDA", "port": 10026, "public": False, },
		{ "name": "Postgrey", "port": 10023, "public": False, },
		{ "name": "Spamassassin", "port": 10025, "public": False, },
		{ "name": "OpenDKIM", "port": 8891, "public": False, },
		{ "name": "OpenDMARC", "port": 8893, "public": False, },
		{ "name": "Memcached", "port": 11211, "public": False, },
		{ "name": "Sieve (dovecot)", "port": 4190, "public": False, },
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
	ret = pool.starmap(check_service, ((i, service, env) for i, service in enumerate(services)), chunksize=1)
	for i, running, fatal2, output2 in sorted(ret):
		if output2 is None: continue # skip check (e.g. no port was set, e.g. no sshd)
		all_running = all_running and running
		fatal = fatal or fatal2
		output2.playback(output)

	if all_running:
		output.print_ok("All system services are running.")

	return not fatal

def check_service(i, service, env):
	if not service["port"]:
		# Skip check (no port, e.g. no sshd).
		return (i, None, None, None)

	output = BufferedOutput()
	running = False
	fatal = False

	# Helper function to make a connection to the service, since we try
	# up to three ways (localhost, IPv4 address, IPv6 address).
	def try_connect(ip):
		# Connect to the given IP address on the service's port with a one-second timeout.
		import socket
		s = socket.socket(socket.AF_INET if ":" not in ip else socket.AF_INET6, socket.SOCK_STREAM)
		s.settimeout(1)
		try:
			s.connect((ip, service["port"]))
			return True
		except OSError as e:
			# timed out or some other odd error
			return False
		finally:
			s.close()

	if service["public"]:
		# Service should be publicly accessible.
		if try_connect(env["PUBLIC_IP"]):
			# IPv4 ok.
			if not env.get("PUBLIC_IPV6") or service.get("ipv6") is False or try_connect(env["PUBLIC_IPV6"]):
				# No IPv6, or service isn't meant to run on IPv6, or IPv6 is good.
				running = True

			# IPv4 ok but IPv6 failed. Try the PRIVATE_IPV6 address to see if the service is bound to the interface.
			elif service["port"] != 53 and try_connect(env["PRIVATE_IPV6"]):
				output.print_error("%s is running (and available over IPv4 and the local IPv6 address), but it is not publicly accessible at %s:%d." % (service['name'], env['PUBLIC_IP'], service['port']))
			else:
				output.print_error("%s is running and available over IPv4 but is not accessible over IPv6 at %s port %d." % (service['name'], env['PUBLIC_IPV6'], service['port']))

		# IPv4 failed. Try the private IP to see if the service is running but not accessible (except DNS because a different service runs on the private IP).
		elif service["port"] != 53 and try_connect("127.0.0.1"):
			output.print_error("%s is running but is not publicly accessible at %s:%d." % (service['name'], env['PUBLIC_IP'], service['port']))
		else:
			output.print_error("%s is not running (port %d)." % (service['name'], service['port']))

		# Why is nginx not running?
		if not running and service["port"] in (80, 443):
			output.print_line(shell('check_output', ['nginx', '-t'], capture_stderr=True, trap=True)[1].strip())

	else:
		# Service should be running locally.
		if try_connect("127.0.0.1"):
			running = True
		else:
			output.print_error("%s is not running (port %d)." % (service['name'], service['port']))

	# Flag if local DNS is not running.
	if not running and service["port"] == 53 and service["public"] == False:
		fatal = True

	return (i, running, fatal, output)

def run_system_checks(rounded_values, env, output):
	check_ssh_password(env, output)
	check_software_updates(env, output)
	check_miab_version(env, output)
	check_system_aliases(env, output)
	check_free_disk_space(rounded_values, env, output)

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
	check_alias_exists("System administrator address", "administrator@" + env['PRIMARY_HOSTNAME'], env, output)

def check_free_disk_space(rounded_values, env, output):
	# Check free disk space.
	st = os.statvfs(env['STORAGE_ROOT'])
	bytes_total = st.f_blocks * st.f_frsize
	bytes_free = st.f_bavail * st.f_frsize
	if not rounded_values:
		disk_msg = "The disk has %s GB space remaining." % str(round(bytes_free/1024.0/1024.0/1024.0*10.0)/10)
	else:
		disk_msg = "The disk has less than %s%% space left." % str(round(bytes_free/bytes_total/10 + .5)*10)
	if bytes_free > .3 * bytes_total:
		output.print_ok(disk_msg)
	elif bytes_free > .15 * bytes_total:
		output.print_warning(disk_msg)
	else:
		output.print_error(disk_msg)

def run_network_checks(env, output):
	# Also see setup/network-checks.sh.

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

def run_domain_checks(rounded_time, env, output, pool):
	# Get the list of domains we handle mail for.
	mail_domains = get_mail_domains(env)

	# Get the list of domains we serve DNS zones for (i.e. does not include subdomains).
	dns_zonefiles = dict(get_dns_zones(env))
	dns_domains = set(dns_zonefiles)

	# Get the list of domains we serve HTTPS for.
	web_domains = set(get_web_domains(env))

	domains_to_check = mail_domains | dns_domains | web_domains

	# Get the list of domains that we don't serve web for because of a custom CNAME/A record.
	domains_with_a_records = get_domains_with_a_records(env)

	ssl_certificates = get_ssl_certificates(env)

	# Serial version:
	#for domain in sort_domains(domains_to_check, env):
	#	run_domain_checks_on_domain(domain, rounded_time, env, dns_domains, dns_zonefiles, mail_domains, web_domains)

	# Parallelize the checks across a worker pool.
	args = ((domain, rounded_time, env, dns_domains, dns_zonefiles, mail_domains, web_domains, domains_with_a_records, ssl_certificates)
		for domain in domains_to_check)
	ret = pool.starmap(run_domain_checks_on_domain, args, chunksize=1)
	ret = dict(ret) # (domain, output) => { domain: output }
	for domain in sort_domains(ret, env):
		ret[domain].playback(output)

def run_domain_checks_on_domain(domain, rounded_time, env, dns_domains, dns_zonefiles, mail_domains, web_domains, domains_with_a_records, ssl_certificates):
	output = BufferedOutput()

	# The domain is IDNA-encoded in the database, but for display use Unicode.
	try:
		domain_display = idna.decode(domain.encode('ascii'))
		output.add_heading(domain_display)
	except (ValueError, UnicodeError, idna.IDNAError) as e:
		# Looks like we have some invalid data in our database.
		output.add_heading(domain)
		output.print_error("Domain name is invalid: " + str(e))

	if domain == env["PRIMARY_HOSTNAME"]:
		check_primary_hostname_dns(domain, env, output, dns_domains, dns_zonefiles)

	if domain in dns_domains:
		check_dns_zone(domain, env, output, dns_zonefiles)

	if domain in mail_domains:
		check_mail_domain(domain, env, output)

	if domain in web_domains:
		check_web_domain(domain, rounded_time, ssl_certificates, env, output)

	if domain in dns_domains:
		check_dns_zone_suggestions(domain, env, output, dns_zonefiles, domains_with_a_records)

	return (domain, output)

def check_primary_hostname_dns(domain, env, output, dns_domains, dns_zonefiles):
	# If a DS record is set on the zone containing this domain, check DNSSEC now.
	has_dnssec = False
	for zone in dns_domains:
		if zone == domain or domain.endswith("." + zone):
			if query_dns(zone, "DS", nxdomain=None) is not None:
				has_dnssec = True
				check_dnssec(zone, env, output, dns_zonefiles, is_checking_primary=True)

	ip = query_dns(domain, "A")
	ns_ips = query_dns("ns1." + domain, "A") + '/' + query_dns("ns2." + domain, "A")
	my_ips = env['PUBLIC_IP'] + ((" / "+env['PUBLIC_IPV6']) if env.get("PUBLIC_IPV6") else "")

	# Check that the ns1/ns2 hostnames resolve to A records. This information probably
	# comes from the TLD since the information is set at the registrar as glue records.
	# We're probably not actually checking that here but instead checking that we, as
	# the nameserver, are reporting the right info --- but if the glue is incorrect this
	# will probably fail.
	if ns_ips == env['PUBLIC_IP'] + '/' + env['PUBLIC_IP']:
		output.print_ok("Nameserver glue records are correct at registrar. [ns1/ns2.%s ↦ %s]" % (env['PRIMARY_HOSTNAME'], env['PUBLIC_IP']))

	elif ip == env['PUBLIC_IP']:
		# The NS records are not what we expect, but the domain resolves correctly, so
		# the user may have set up external DNS. List this discrepancy as a warning.
		output.print_warning("""Nameserver glue records (ns1.%s and ns2.%s) should be configured at your domain name
			registrar as having the IP address of this box (%s). They currently report addresses of %s. If you have set up External DNS, this may be OK."""
			% (env['PRIMARY_HOSTNAME'], env['PRIMARY_HOSTNAME'], env['PUBLIC_IP'], ns_ips))

	else:
		output.print_error("""Nameserver glue records are incorrect. The ns1.%s and ns2.%s nameservers must be configured at your domain name
			registrar as having the IP address %s. They currently report addresses of %s. It may take several hours for
			public DNS to update after a change."""
			% (env['PRIMARY_HOSTNAME'], env['PRIMARY_HOSTNAME'], env['PUBLIC_IP'], ns_ips))

	# Check that PRIMARY_HOSTNAME resolves to PUBLIC_IP[V6] in public DNS.
	ipv6 = query_dns(domain, "AAAA") if env.get("PUBLIC_IPV6") else None
	if ip == env['PUBLIC_IP'] and ipv6 in (None, env['PUBLIC_IPV6']):
		output.print_ok("Domain resolves to box's IP address. [%s ↦ %s]" % (env['PRIMARY_HOSTNAME'], my_ips))
	else:
		output.print_error("""This domain must resolve to your box's IP address (%s) in public DNS but it currently resolves
			to %s. It may take several hours for public DNS to update after a change. This problem may result from other
			issues listed above."""
			% (my_ips, ip + ((" / " + ipv6) if ipv6 is not None else "")))


	# Check reverse DNS matches the PRIMARY_HOSTNAME. Note that it might not be
	# a DNS zone if it is a subdomain of another domain we have a zone for.
	existing_rdns_v4 = query_dns(dns.reversename.from_address(env['PUBLIC_IP']), "PTR")
	existing_rdns_v6 = query_dns(dns.reversename.from_address(env['PUBLIC_IPV6']), "PTR") if env.get("PUBLIC_IPV6") else None
	if existing_rdns_v4 == domain and existing_rdns_v6 in (None, domain):
		output.print_ok("Reverse DNS is set correctly at ISP. [%s ↦ %s]" % (my_ips, env['PRIMARY_HOSTNAME']))
	elif existing_rdns_v4 == existing_rdns_v6 or existing_rdns_v6 is None:
		output.print_error("""Your box's reverse DNS is currently %s, but it should be %s. Your ISP or cloud provider will have instructions
			on setting up reverse DNS for your box.""" % (existing_rdns_v4, domain) )
	else:
		output.print_error("""Your box's reverse DNS is currently %s (IPv4) and %s (IPv6), but it should be %s. Your ISP or cloud provider will have instructions
			on setting up reverse DNS for your box.""" % (existing_rdns_v4, existing_rdns_v6, domain) )

	# Check the TLSA record.
	tlsa_qname = "_25._tcp." + domain
	tlsa25 = query_dns(tlsa_qname, "TLSA", nxdomain=None)
	tlsa25_expected = build_tlsa_record(env)
	if tlsa25 == tlsa25_expected:
		output.print_ok("""The DANE TLSA record for incoming mail is correct (%s).""" % tlsa_qname,)
	elif tlsa25 is None:
		if has_dnssec:
			# Omit a warning about it not being set if DNSSEC isn't enabled,
			# since TLSA shouldn't be used without DNSSEC.
			output.print_warning("""The DANE TLSA record for incoming mail is not set. This is optional.""")
	else:
		output.print_error("""The DANE TLSA record for incoming mail (%s) is not correct. It is '%s' but it should be '%s'.
			It may take several hours for public DNS to update after a change."""
                        % (tlsa_qname, tlsa25, tlsa25_expected))

	# Check that the hostmaster@ email address exists.
	check_alias_exists("Hostmaster contact address", "hostmaster@" + domain, env, output)

def check_alias_exists(alias_name, alias, env, output):
	mail_aliases = dict([(address, receivers) for address, receivers, *_ in get_mail_aliases(env)])
	if alias in mail_aliases:
		if mail_aliases[alias]:
			output.print_ok("%s exists as a mail alias. [%s ↦ %s]" % (alias_name, alias, mail_aliases[alias]))
		else:
			output.print_error("""You must set the destination of the mail alias for %s to direct email to you or another administrator.""" % alias)
	else:
		output.print_error("""You must add a mail alias for %s which directs email to you or another administrator.""" % alias)

def check_dns_zone(domain, env, output, dns_zonefiles):
	# If a DS record is set at the registrar, check DNSSEC first because it will affect the NS query.
	# If it is not set, we suggest it last.
	if query_dns(domain, "DS", nxdomain=None) is not None:
		check_dnssec(domain, env, output, dns_zonefiles)

	# We provide a DNS zone for the domain. It should have NS records set up
	# at the domain name's registrar pointing to this box. The secondary DNS
	# server may be customized.
	# (I'm not sure whether this necessarily tests the TLD's configuration,
	# as it should, or if one successful NS line at the TLD will result in
	# this query being answered by the box, which would mean the test is only
	# half working.)

	custom_dns_records = list(get_custom_dns_config(env)) # generator => list so we can reuse it
	correct_ip = get_custom_dns_record(custom_dns_records, domain, "A") or env['PUBLIC_IP']
	custom_secondary_ns = get_secondary_dns(custom_dns_records, mode="NS")
	secondary_ns = custom_secondary_ns or ["ns2." + env['PRIMARY_HOSTNAME']]

	existing_ns = query_dns(domain, "NS")
	correct_ns = "; ".join(sorted(["ns1." + env['PRIMARY_HOSTNAME']] + secondary_ns))
	ip = query_dns(domain, "A")

	probably_external_dns = False

	if existing_ns.lower() == correct_ns.lower():
		output.print_ok("Nameservers are set correctly at registrar. [%s]" % correct_ns)
	elif ip == correct_ip:
		# The domain resolves correctly, so maybe the user is using External DNS.
		output.print_warning("""The nameservers set on this domain at your domain name registrar should be %s. They are currently %s.
			If you are using External DNS, this may be OK."""
				% (correct_ns, existing_ns) )
		probably_external_dns = True
	else:
		output.print_error("""The nameservers set on this domain are incorrect. They are currently %s. Use your domain name registrar's
			control panel to set the nameservers to %s."""
				% (existing_ns, correct_ns) )

	# Check that each custom secondary nameserver resolves the IP address.
	
	if custom_secondary_ns and not probably_external_dns:
		for ns in custom_secondary_ns:
			# We must first resolve the nameserver to an IP address so we can query it.
			ns_ip = query_dns(ns, "A")
			if not ns_ip:
				output.print_error("Secondary nameserver %s is not valid (it doesn't resolve to an IP address)." % ns)
				continue

			# Now query it to see what it says about this domain.
			ip = query_dns(domain, "A", at=ns_ip, nxdomain=None)
			if ip == correct_ip:
				output.print_ok("Secondary nameserver %s resolved the domain correctly." % ns)
			elif ip is None:
				output.print_error("Secondary nameserver %s is not configured to resolve this domain." % ns)
			else:
				output.print_error("Secondary nameserver %s is not configured correctly. (It resolved this domain as %s. It should be %s.)" % (ns, ip, env['PUBLIC_IP']))

def check_dns_zone_suggestions(domain, env, output, dns_zonefiles, domains_with_a_records):
	# Warn if a custom DNS record is preventing this or the automatic www redirect from
	# being served.
	if domain in domains_with_a_records:
		output.print_warning("""Web has been disabled for this domain because you have set a custom DNS record.""")
	if "www." + domain in domains_with_a_records:
		output.print_warning("""A redirect from 'www.%s' has been disabled for this domain because you have set a custom DNS record on the www subdomain.""" % domain)

	# Since DNSSEC is optional, if a DS record is NOT set at the registrar suggest it.
	# (If it was set, we did the check earlier.)
	if query_dns(domain, "DS", nxdomain=None) is None:
		check_dnssec(domain, env, output, dns_zonefiles)


def check_dnssec(domain, env, output, dns_zonefiles, is_checking_primary=False):
	# See if the domain has a DS record set at the registrar. The DS record may have
	# several forms. We have to be prepared to check for any valid record. We've
	# pre-generated all of the valid digests --- read them in.
	ds_file = '/etc/nsd/zones/' + dns_zonefiles[domain] + '.ds'
	if not os.path.exists(ds_file): return # Domain is in our database but DNS has not yet been updated.
	ds_correct = open(ds_file).read().strip().split("\n")
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
			output.print_warning("""This domain's DNSSEC DS record is not set. The DS record is optional. The DS record activates DNSSEC.
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

	recommended_mx = "10 " + env['PRIMARY_HOSTNAME']
	mx = query_dns(domain, "MX", nxdomain=None)

	if mx is None:
		mxhost = None
	else:
		# query_dns returns a semicolon-delimited list
		# of priority-host pairs.
		mxhost = mx.split('; ')[0].split(' ')[1]

	if mxhost == None:
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
					change. This problem may result from other issues listed here.""" % (recommended_mx,))

	elif mxhost == env['PRIMARY_HOSTNAME']:
		good_news = "Domain's email is directed to this domain. [%s ↦ %s]" % (domain, mx)
		if mx != recommended_mx:
			good_news += "  This configuration is non-standard.  The recommended configuration is '%s'." % (recommended_mx,)
		output.print_ok(good_news)
	else:
		output.print_error("""This domain's DNS MX record is incorrect. It is currently set to '%s' but should be '%s'. Mail will not
			be delivered to this box. It may take several hours for public DNS to update after a change. This problem may result from
			other issues listed here.""" % (mx, recommended_mx))

	# Check that the postmaster@ email address exists. Not required if the domain has a
	# catch-all address or domain alias.
	if "@" + domain not in [address for address, *_ in get_mail_aliases(env)]:
		check_alias_exists("Postmaster contact address", "postmaster@" + domain, env, output)

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

def check_web_domain(domain, rounded_time, ssl_certificates, env, output):
	# See if the domain's A record resolves to our PUBLIC_IP. This is already checked
	# for PRIMARY_HOSTNAME, for which it is required for mail specifically. For it and
	# other domains, it is required to access its website.
	if domain != env['PRIMARY_HOSTNAME']:
		ip = query_dns(domain, "A")
		if ip == env['PUBLIC_IP']:
			output.print_ok("Domain resolves to this box's IP address. [%s ↦ %s]" % (domain, env['PUBLIC_IP']))
		else:
			output.print_error("""This domain should resolve to your box's IP address (%s) if you would like the box to serve
				webmail or a website on this domain. The domain currently resolves to %s in public DNS. It may take several hours for
				public DNS to update after a change. This problem may result from other issues listed here.""" % (env['PUBLIC_IP'], ip))

	# We need a SSL certificate for PRIMARY_HOSTNAME because that's where the
	# user will log in with IMAP or webmail. Any other domain we serve a
	# website for also needs a signed certificate.
	check_ssl_cert(domain, rounded_time, ssl_certificates, env, output)

def query_dns(qname, rtype, nxdomain='[Not Set]', at=None):
	# Make the qname absolute by appending a period. Without this, dns.resolver.query
	# will fall back a failed lookup to a second query with this machine's hostname
	# appended. This has been causing some false-positive Spamhaus reports. The
	# reverse DNS lookup will pass a dns.name.Name instance which is already
	# absolute so we should not modify that.
	if isinstance(qname, str):
		qname += "."

	# Use the default nameservers (as defined by the system, which is our locally
	# running bind server), or if the 'at' argument is specified, use that host
	# as the nameserver.
	resolver = dns.resolver.get_default_resolver()
	if at:
		resolver = dns.resolver.Resolver()
		resolver.nameservers = [at]

	# Set a timeout so that a non-responsive server doesn't hold us back.
	resolver.timeout = 5

	# Do the query.
	try:
		response = resolver.query(qname, rtype)
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

def check_ssl_cert(domain, rounded_time, ssl_certificates, env, output):
	# Check that SSL certificate is signed.

	# Skip the check if the A record is not pointed here.
	if query_dns(domain, "A", None) not in (env['PUBLIC_IP'], None): return

	# Where is the SSL stored?
	x = get_domain_ssl_files(domain, ssl_certificates, env, allow_missing_cert=True)

	if x is None:
		output.print_warning("""No SSL certificate is installed for this domain. Visitors to a website on
			this domain will get a security warning. If you are not serving a website on this domain, you do
			not need to take any action. Use the SSL Certificates page in the control panel to install a
			SSL certificate.""")
		return

	ssl_key, ssl_certificate, ssl_via = x

	# Check that the certificate is good.

	cert_status, cert_status_details = check_certificate(domain, ssl_certificate, ssl_key, rounded_time=rounded_time)

	if cert_status == "OK":
		# The certificate is ok. The details has expiry info.
		output.print_ok("SSL certificate is signed & valid. %s %s" % (ssl_via if ssl_via else "", cert_status_details))

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
			static site hosting). Use the SSL Certificates page in the control panel to install a signed SSL certificate.
			You may choose to leave the self-signed certificate in place and confirm the security exception, but check that
			the certificate fingerprint matches the following:""")
			output.print_line("")
			output.print_line("   " + fingerprint, monospace=True)
		else:
			output.print_error("""The SSL certificate for this domain is self-signed.""")

	else:
		output.print_error("The SSL certificate has a problem: " + cert_status)
		if cert_status_details:
			output.print_line("")
			output.print_line(cert_status_details)
			output.print_line("")

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

def what_version_is_this(env):
	# This function runs `git describe --abbrev=0` on the Mail-in-a-Box installation directory.
	# Git may not be installed and Mail-in-a-Box may not have been cloned from github,
	# so this function may raise all sorts of exceptions.
	miab_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
	tag = shell("check_output", ["/usr/bin/git", "describe", "--abbrev=0"], env={"GIT_DIR": os.path.join(miab_dir, '.git')}).strip()
	return tag

def get_latest_miab_version():
	# This pings https://mailinabox.email/bootstrap.sh and extracts the tag named in
	# the script to determine the current product version.
	import urllib.request
	return re.search(b'TAG=(.*)', urllib.request.urlopen("https://mailinabox.email/bootstrap.sh?ping=1").read()).group(1).decode("utf8")

def check_miab_version(env, output):
	config = load_settings(env)

	if config.get("privacy", True):
		output.print_warning("Mail-in-a-Box version check disabled by privacy setting.")
	else:
		this_ver = what_version_is_this(env)
		latest_ver = get_latest_miab_version()
		if this_ver == latest_ver:
			output.print_ok("Mail-in-a-Box is up to date. You are running version %s." % this_ver)
		else:
			output.print_error("A new version of Mail-in-a-Box is available. You are running version %s. The latest version is %s. For upgrade instructions, see https://mailinabox.email. "
				% (this_ver, latest_ver))

def run_and_output_changes(env, pool, send_via_email):
	import json
	from difflib import SequenceMatcher

	if not send_via_email:
		out = ConsoleOutput()
	else:
		import io
		out = FileOutput(io.StringIO(""), 70)

	# Run status checks.
	cur = BufferedOutput()
	run_checks(True, env, cur, pool)

	# Load previously saved status checks.
	cache_fn = "/var/cache/mailinabox/status_checks.json"
	if os.path.exists(cache_fn):
		prev = json.load(open(cache_fn))

		# Group the serial output into categories by the headings.
		def group_by_heading(lines):
			from collections import OrderedDict
			ret = OrderedDict()
			k = []
			ret["No Category"] = k
			for line_type, line_args, line_kwargs in lines:
				if line_type == "add_heading":
					k = []
					ret[line_args[0]] = k
				else:
					k.append((line_type, line_args, line_kwargs))
			return ret
		prev_status = group_by_heading(prev)
		cur_status = group_by_heading(cur.buf)

		# Compare the previous to the current status checks
		# category by category.
		for category, cur_lines in cur_status.items():
			if category not in prev_status:
				out.add_heading(category + " -- Added")
				BufferedOutput(with_lines=cur_lines).playback(out)
			else:
				# Actual comparison starts here...
				prev_lines = prev_status[category]
				def stringify(lines):
					return [json.dumps(line) for line in lines]
				diff = SequenceMatcher(None, stringify(prev_lines), stringify(cur_lines)).get_opcodes()
				for op, i1, i2, j1, j2 in diff:
					if op == "replace":
						out.add_heading(category + " -- Previously:")
					elif op == "delete":
						out.add_heading(category + " -- Removed")
					if op in ("replace", "delete"):
						BufferedOutput(with_lines=prev_lines[i1:i2]).playback(out)

					if op == "replace":
						out.add_heading(category + " -- Currently:")
					elif op == "insert":
						out.add_heading(category + " -- Added")
					if op in ("replace", "insert"):
						BufferedOutput(with_lines=cur_lines[j1:j2]).playback(out)

		for category, prev_lines in prev_status.items():
			if category not in cur_status:
				out.add_heading(category)
				out.print_warning("This section was removed.")

	if send_via_email:
		# If there were changes, send off an email.
		buf = out.buf.getvalue()
		if len(buf) > 0:
			# create MIME message
			from email.message import Message
			msg = Message()
			msg['From'] = "\"%s\" <administrator@%s>" % (env['PRIMARY_HOSTNAME'], env['PRIMARY_HOSTNAME'])
			msg['To'] = "administrator@%s" % env['PRIMARY_HOSTNAME']
			msg['Subject'] = "[%s] Status Checks Change Notice" % env['PRIMARY_HOSTNAME']
			msg.set_payload(buf, "UTF-8")

			# send to administrator@
			import smtplib
			mailserver = smtplib.SMTP('localhost', 25)
			mailserver.ehlo()
			mailserver.sendmail(
				"administrator@%s" % env['PRIMARY_HOSTNAME'], # MAIL FROM
				"administrator@%s" % env['PRIMARY_HOSTNAME'], # RCPT TO
				msg.as_string())
			mailserver.quit()

	# Store the current status checks output for next time.
	os.makedirs(os.path.dirname(cache_fn), exist_ok=True)
	with open(cache_fn, "w") as f:
		json.dump(cur.buf, f, indent=True)

class FileOutput:
	def __init__(self, buf, width):
		self.buf = buf
		self.width = width

	def add_heading(self, heading):
		print(file=self.buf)
		print(heading, file=self.buf)
		print("=" * len(heading), file=self.buf)

	def print_ok(self, message):
		self.print_block(message, first_line="✓  ")

	def print_error(self, message):
		self.print_block(message, first_line="✖  ")

	def print_warning(self, message):
		self.print_block(message, first_line="?  ")

	def print_block(self, message, first_line="   "):
		print(first_line, end='', file=self.buf)
		message = re.sub("\n\s*", " ", message)
		words = re.split("(\s+)", message)
		linelen = 0
		for w in words:
			if linelen + len(w) > self.width-1-len(first_line):
				print(file=self.buf)
				print("   ", end="", file=self.buf)
				linelen = 0
			if linelen == 0 and w.strip() == "": continue
			print(w, end="", file=self.buf)
			linelen += len(w)
		print(file=self.buf)

	def print_line(self, message, monospace=False):
		for line in message.split("\n"):
			self.print_block(line)

class ConsoleOutput(FileOutput):
	def __init__(self):
		self.buf = sys.stdout
		try:
			self.width = int(shell('check_output', ['stty', 'size']).split()[1])
		except:
			self.width = 76

class BufferedOutput:
	# Record all of the instance method calls so we can play them back later.
	def __init__(self, with_lines=None):
		self.buf = [] if not with_lines else with_lines
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
	from utils import load_environment

	env = load_environment()
	pool = multiprocessing.pool.Pool(processes=10)

	if len(sys.argv) == 1:
		run_checks(False, env, ConsoleOutput(), pool)

	elif sys.argv[1] == "--show-changes":
		run_and_output_changes(env, pool, sys.argv[-1] == "--smtp")

	elif sys.argv[1] == "--check-primary-hostname":
		# See if the primary hostname appears resolvable and has a signed certificate.
		domain = env['PRIMARY_HOSTNAME']
		if query_dns(domain, "A") != env['PUBLIC_IP']:
			sys.exit(1)
		ssl_certificates = get_ssl_certificates(env)
		ssl_key, ssl_certificate, ssl_via = get_domain_ssl_files(domain, ssl_certificates, env)
		if not os.path.exists(ssl_certificate):
			sys.exit(1)
		cert_status, cert_status_details = check_certificate(domain, ssl_certificate, ssl_key, warn_if_expiring_soon=False)
		if cert_status != "OK":
			sys.exit(1)
		sys.exit(0)

	elif sys.argv[1] == "--version":
		print(what_version_is_this(env))
