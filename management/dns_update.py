#!/usr/local/lib/mailinabox/env/bin/python

# Creates DNS zone files for all of the domains of all of the mail users
# and mail aliases and restarts nsd.
########################################################################

import sys, os, os.path, datetime, re, hashlib, base64
import ipaddress
import rtyaml
import dns.resolver

from utils import shell, load_env_vars_from_file, safe_domain_name, sort_domains, get_ssh_port
from ssl_certificates import get_ssl_certificates, check_certificate
import contextlib

# From https://stackoverflow.com/questions/3026957/how-to-validate-a-domain-name-using-regex-php/16491074#16491074
# This regular expression matches domain names according to RFCs, it also accepts fqdn with an leading dot,
# underscores, as well as asterisks which are allowed in domain names but not hostnames (i.e. allowed in
# DNS but not in URLs), which are common in certain record types like for DKIM.
DOMAIN_RE = r"^(?!\-)(?:[*][.])?(?:[a-zA-Z\d\-_]{0,62}[a-zA-Z\d_]\.){1,126}(?!\d+)[a-zA-Z\d_]{1,63}(\.?)$"

def get_dns_domains(env):
	# Add all domain names in use by email users and mail aliases, any
	# domains we serve web for (except www redirects because that would
	# lead to infinite recursion here) and ensure PRIMARY_HOSTNAME is in the list.
	from mailconfig import get_mail_domains
	from web_update import get_web_domains
	domains = set()
	domains |= set(get_mail_domains(env))
	domains |= set(get_web_domains(env, include_www_redirects=False))
	domains.add(env['PRIMARY_HOSTNAME'])
	return domains

def get_dns_zones(env):
	# What domains should we create DNS zones for? Never create a zone for
	# a domain & a subdomain of that domain.
	domains = get_dns_domains(env)

	# Exclude domains that are subdomains of other domains we know. Proceed
	# by looking at shorter domains first.
	zone_domains = set()
	for domain in sorted(domains, key=len):
		for d in zone_domains:
			if domain.endswith("." + d):
				# We found a parent domain already in the list.
				break
		else:
			# 'break' did not occur: there is no parent domain.
			zone_domains.add(domain)

	# Make a nice and safe filename for each domain.
	zonefiles = [[domain, safe_domain_name(domain) + ".txt"] for domain in zone_domains]

	# Sort the list so that the order is nice and so that nsd.conf has a
	# stable order so we don't rewrite the file & restart the service
	# meaninglessly.
	zone_order = sort_domains([ zone[0] for zone in zonefiles ], env)
	zonefiles.sort(key = lambda zone : zone_order.index(zone[0]) )

	return zonefiles

def do_dns_update(env, force=False):
	# Write zone files.
	os.makedirs('/etc/nsd/zones', exist_ok=True)
	zonefiles = []
	updated_domains = []
	for (domain, zonefile, records) in build_zones(env):
		# The final set of files will be signed.
		zonefiles.append((domain, zonefile + ".signed"))

		# See if the zone has changed, and if so update the serial number
		# and write the zone file.
		if not write_nsd_zone(domain, "/etc/nsd/zones/" + zonefile, records, env, force):
			# Zone was not updated. There were no changes.
			continue

		# Mark that we just updated this domain.
		updated_domains.append(domain)

		# Sign the zone.
		#
		# Every time we sign the zone we get a new result, which means
		# we can't sign a zone without bumping the zone's serial number.
		# Thus we only sign a zone if write_nsd_zone returned True
		# indicating the zone changed, and thus it got a new serial number.
		# write_nsd_zone is smart enough to check if a zone's signature
		# is nearing expiration and if so it'll bump the serial number
		# and return True so we get a chance to re-sign it.
		sign_zone(domain, zonefile, env)

	# Write the main nsd.conf file.
	if write_nsd_conf(zonefiles, list(get_custom_dns_config(env)), env):
		# Make sure updated_domains contains *something* if we wrote an updated
		# nsd.conf so that we know to restart nsd.
		if len(updated_domains) == 0:
			updated_domains.append("DNS configuration")

	# Tell nsd to reload changed zone files.
	if len(updated_domains) > 0:
		# 'reconfig' is needed if there are added or removed zones, but
		# it may not reload existing zones, so we call 'reload' too. If
		# nsd isn't running, nsd-control fails, so in that case revert
		# to restarting nsd to make sure it is running. Restarting nsd
		# should also refresh everything.
		try:
			shell('check_call', ["/usr/sbin/nsd-control", "reconfig"])
			shell('check_call', ["/usr/sbin/nsd-control", "reload"])
		except:
			shell('check_call', ["/usr/sbin/service", "nsd", "restart"])

	# Write the OpenDKIM configuration tables for all of the mail domains.
	from mailconfig import get_mail_domains
	if write_opendkim_tables(get_mail_domains(env), env):
		# Settings changed. Kick opendkim.
		shell('check_call', ["/usr/sbin/service", "opendkim", "restart"])
		if len(updated_domains) == 0:
			# If this is the only thing that changed?
			updated_domains.append("OpenDKIM configuration")

	# Clear bind9's DNS cache so our own DNS resolver is up to date.
	# (ignore errors with trap=True)
	shell('check_call', ["/usr/sbin/rndc", "flush"], trap=True)

	if len(updated_domains) == 0:
		# if nothing was updated (except maybe OpenDKIM's files), don't show any output
		return ""
	else:
		return "updated DNS: " + ",".join(updated_domains) + "\n"

########################################################################

def build_zones(env):
	# What domains (and their zone filenames) should we build?
	domains = get_dns_domains(env)
	zonefiles = get_dns_zones(env)

	# Create a dictionary of domains to a set of attributes for each
	# domain, such as whether there are mail users at the domain.
	from mailconfig import get_mail_domains
	from web_update import get_web_domains
	mail_domains = set(get_mail_domains(env))
	mail_user_domains = set(get_mail_domains(env, users_only=True)) # i.e. will log in for mail, Nextcloud
	web_domains = set(get_web_domains(env))
	auto_domains = web_domains - set(get_web_domains(env, include_auto=False))
	domains |= auto_domains # www redirects not included in the initial list, see above

	# Add ns1/ns2+PRIMARY_HOSTNAME which must also have A/AAAA records
	# when the box is acting as authoritative DNS server for its domains.
	for ns in ("ns1", "ns2"):
		d = ns + "." + env["PRIMARY_HOSTNAME"]
		domains.add(d)
		auto_domains.add(d)

	domains = {
		domain: {
			"user": domain in mail_user_domains,
			"mail": domain in mail_domains,
			"web": domain in web_domains,
			"auto": domain in auto_domains,
		}
		for domain in domains
	}

	# For MTA-STS, we'll need to check if the PRIMARY_HOSTNAME certificate is
	# singned and valid. Check that now rather than repeatedly for each domain.
	domains[env["PRIMARY_HOSTNAME"]]["certificate-is-valid"] = is_domain_cert_signed_and_valid(env["PRIMARY_HOSTNAME"], env)

	# Load custom records to add to zones.
	additional_records = list(get_custom_dns_config(env))

	# Build DNS records for each zone.
	for domain, zonefile in zonefiles:
		# Build the records to put in the zone.
		records = build_zone(domain, domains, additional_records, env)
		yield (domain, zonefile, records)

def build_zone(domain, domain_properties, additional_records, env, is_zone=True):
	records = []

	# For top-level zones, define the authoritative name servers.
	#
	# Normally we are our own nameservers. Some TLDs require two distinct IP addresses,
	# so we allow the user to override the second nameserver definition so that
	# secondary DNS can be set up elsewhere.
	#
	# 'False' in the tuple indicates these records would not be used if the zone
	# is managed outside of the box.
	if is_zone:
		# Obligatory NS record to ns1.PRIMARY_HOSTNAME.
		records.append((None,  "NS",  "ns1.%s." % env["PRIMARY_HOSTNAME"], False))

		# NS record to ns2.PRIMARY_HOSTNAME or whatever the user overrides.
		# User may provide one or more additional nameservers
		secondary_ns_list = get_secondary_dns(additional_records, mode="NS") \
			or ["ns2." + env["PRIMARY_HOSTNAME"]]
		records.extend((None,  "NS", secondary_ns+'.', False) for secondary_ns in secondary_ns_list)


	# In PRIMARY_HOSTNAME...
	if domain == env["PRIMARY_HOSTNAME"]:
		# Set the A/AAAA records. Do this early for the PRIMARY_HOSTNAME so that the user cannot override them
		# and we can provide different explanatory text.
		records.append((None, "A", env["PUBLIC_IP"], "Required. Sets the IP address of the box."))
		if env.get("PUBLIC_IPV6"): records.append((None, "AAAA", env["PUBLIC_IPV6"], "Required. Sets the IPv6 address of the box."))

		# Add a DANE TLSA record for SMTP.
		records.append(("_25._tcp", "TLSA", build_tlsa_record(env), "Recommended when DNSSEC is enabled. Advertises to mail servers connecting to the box that mandatory encryption should be used."))

		# Add a DANE TLSA record for HTTPS, which some browser extensions might make use of.
		records.append(("_443._tcp", "TLSA", build_tlsa_record(env), "Optional. When DNSSEC is enabled, provides out-of-band HTTPS certificate validation for a few web clients that support it."))

		# Add a SSHFP records to help SSH key validation. One per available SSH key on this system.
		records.extend((None, "SSHFP", value, "Optional. Provides an out-of-band method for verifying an SSH key before connecting. Use 'VerifyHostKeyDNS yes' (or 'VerifyHostKeyDNS ask') when connecting with ssh.") for value in build_sshfp_records())

	# Add DNS records for any subdomains of this domain. We should not have a zone for
	# both a domain and one of its subdomains.
	if is_zone: # don't recurse when we're just loading data for a subdomain
		subdomains = [d for d in domain_properties if d.endswith("." + domain)]
		for subdomain in subdomains:
			subdomain_qname = subdomain[0:-len("." + domain)]
			subzone = build_zone(subdomain, domain_properties, additional_records, env, is_zone=False)
			for child_qname, child_rtype, child_value, child_explanation in subzone:
				if child_qname is None:
					child_qname = subdomain_qname
				else:
					child_qname += "." + subdomain_qname
				records.append((child_qname, child_rtype, child_value, child_explanation))

	has_rec_base = list(records) # clone current state
	def has_rec(qname, rtype, prefix=None):
		return any(rec[0] == qname and rec[1] == rtype and (prefix is None or rec[2].startswith(prefix)) for rec in has_rec_base)

	# The user may set other records that don't conflict with our settings.
	# Don't put any TXT records above this line, or it'll prevent any custom TXT records.
	for qname, rtype, value in filter_custom_records(domain, additional_records):
		# Don't allow custom records for record types that override anything above.
		# But allow multiple custom records for the same rtype --- see how has_rec_base is used.
		if has_rec(qname, rtype): continue

		# The "local" keyword on A/AAAA records are short-hand for our own IP.
		# This also flags for web configuration that the user wants a website here.
		if rtype == "A" and value == "local":
			value = env["PUBLIC_IP"]
		if rtype == "AAAA" and value == "local":
			if "PUBLIC_IPV6" in env:
				value = env["PUBLIC_IPV6"]
			else:
				continue
		records.append((qname, rtype, value, "(Set by user.)"))

	# Add A/AAAA defaults if not overridden by the user's custom settings (and not otherwise configured).
	# Any CNAME or A record on the qname overrides A and AAAA. But when we set the default A record,
	# we should not cause the default AAAA record to be skipped because it thinks a custom A record
	# was set. So set has_rec_base to a clone of the current set of DNS settings, and don't update
	# during this process.
	has_rec_base = list(records)
	a_expl = "Required. May have a different value. Sets the IP address that %s resolves to for web hosting and other services besides mail. The A record must be present but its value does not affect mail delivery." % domain
	if domain_properties[domain]["auto"]:
		if domain.startswith(("ns1.", "ns2.")): a_expl = False # omit from 'External DNS' page since this only applies if box is its own DNS server
		if domain.startswith("www."): a_expl = "Optional. Sets the IP address that %s resolves to so that the box can provide a redirect to the parent domain." % domain
		if domain.startswith("mta-sts."): a_expl = "Optional. MTA-STS Policy Host serving /.well-known/mta-sts.txt."
		if domain.startswith("autoconfig."): a_expl = "Provides email configuration autodiscovery support for Thunderbird Autoconfig."
		if domain.startswith("autodiscover."): a_expl = "Provides email configuration autodiscovery support for Z-Push ActiveSync Autodiscover."
	defaults = [
		(None,  "A",    env["PUBLIC_IP"], a_expl),
		(None,  "AAAA", env.get('PUBLIC_IPV6'), "Optional. Sets the IPv6 address that %s resolves to, e.g. for web hosting. (It is not necessary for receiving mail on this domain.)" % domain),
	]
	for qname, rtype, value, explanation in defaults:
		if value is None or value.strip() == "": continue # skip IPV6 if not set
		if not is_zone and qname == "www": continue # don't create any default 'www' subdomains on what are themselves subdomains
		# Set the default record, but not if:
		# (1) there is not a user-set record of the same type already
		# (2) there is not a CNAME record already, since you can't set both and who knows what takes precedence
		# (2) there is not an A record already (if this is an A record this is a dup of (1), and if this is an AAAA record then don't set a default AAAA record if the user sets a custom A record, since the default wouldn't make sense and it should not resolve if the user doesn't provide a new AAAA record)
		if not has_rec(qname, rtype) and not has_rec(qname, "CNAME") and not has_rec(qname, "A"):
			records.append((qname, rtype, value, explanation))

	# Don't pin the list of records that has_rec checks against anymore.
	has_rec_base = records

	if domain_properties[domain]["mail"]:
		# The MX record says where email for the domain should be delivered: Here!
		if not has_rec(None, "MX", prefix="10 "):
			records.append((None,  "MX",  "10 %s." % env["PRIMARY_HOSTNAME"], "Required. Specifies the hostname (and priority) of the machine that handles @%s mail." % domain))

		# SPF record: Permit the box ('mx', see above) to send mail on behalf of
		# the domain, and no one else.
		# Skip if the user has set a custom SPF record.
		if not has_rec(None, "TXT", prefix="v=spf1 "):
			records.append((None,  "TXT", 'v=spf1 mx -all', "Recommended. Specifies that only the box is permitted to send @%s mail." % domain))

		# Append the DKIM TXT record to the zone as generated by OpenDKIM.
		# Skip if the user has set a DKIM record already.
		opendkim_record_file = os.path.join(env['STORAGE_ROOT'], 'mail/dkim/mail.txt')
		with open(opendkim_record_file, encoding="utf-8") as orf:
			m = re.match(r'(\S+)\s+IN\s+TXT\s+\( ((?:"[^"]+"\s+)+)\)', orf.read(), re.S)
			val = "".join(re.findall(r'"([^"]+)"', m.group(2)))
			if not has_rec(m.group(1), "TXT", prefix="v=DKIM1; "):
				records.append((m.group(1), "TXT", val, "Recommended. Provides a way for recipients to verify that this machine sent @%s mail." % domain))

		# Append a DMARC record.
		# Skip if the user has set a DMARC record already.
		if not has_rec("_dmarc", "TXT", prefix="v=DMARC1; "):
			records.append(("_dmarc", "TXT", 'v=DMARC1; p=quarantine;', "Recommended. Specifies that mail that does not originate from the box but claims to be from @%s or which does not have a valid DKIM signature is suspect and should be quarantined by the recipient's mail system." % domain))

	if domain_properties[domain]["user"]:
		# Add CardDAV/CalDAV SRV records on the non-primary hostname that points to the primary hostname
		# for autoconfiguration of mail clients (so only domains hosting user accounts need it).
		# The SRV record format is priority (0, whatever), weight (0, whatever), port, service provider hostname (w/ trailing dot).
		if domain != env["PRIMARY_HOSTNAME"]:
			for dav in ("card", "cal"):
				qname = "_" + dav + "davs._tcp"
				if not has_rec(qname, "SRV"):
					records.append((qname, "SRV", "0 0 443 " + env["PRIMARY_HOSTNAME"] + ".", "Recommended. Specifies the hostname of the server that handles CardDAV/CalDAV services for email addresses on this domain."))

	# If this is a domain name that there are email addresses configured for, i.e. "something@"
	# this domain name, then the domain name is a MTA-STS (https://tools.ietf.org/html/rfc8461)
	# Policy Domain.
	#
	# A "_mta-sts" TXT record signals the presence of a MTA-STS policy. The id field helps clients
	# cache the policy. It should be stable so we don't update DNS unnecessarily but change when
	# the policy changes. It must be at most 32 letters and numbers, so we compute a hash of the
	# policy file.
	#
	# The policy itself is served at the "mta-sts" (no underscore) subdomain over HTTPS. Therefore
	# the TLS certificate used by Postfix for STARTTLS must be a valid certificate for the MX
	# domain name (PRIMARY_HOSTNAME) *and* the TLS certificate used by nginx for HTTPS on the mta-sts
	# subdomain must be valid certificate for that domain. Do not set an MTA-STS policy if either
	# certificate in use is not valid (e.g. because it is self-signed and a valid certificate has not
	# yet been provisioned). Since we cannot provision a certificate without A/AAAA records, we
	# always set them (by including them in the www domains) --- only the TXT records depend on there
	# being valid certificates.
	mta_sts_records = [ ]
	if domain_properties[domain]["mail"] \
	  and domain_properties[env["PRIMARY_HOSTNAME"]]["certificate-is-valid"] \
	  and is_domain_cert_signed_and_valid("mta-sts." + domain, env):
		# Compute an up-to-32-character hash of the policy file. We'll take a SHA-1 hash of the policy
		# file (20 bytes) and encode it as base-64 (28 bytes, using alphanumeric alternate characters
		# instead of '+' and '/' which are not allowed in an MTA-STS policy id) but then just take its
		# first 20 characters, which is more than sufficient to change whenever the policy file changes
		# (and ensures any '=' padding at the end of the base64 encoding is dropped).
		with open("/var/lib/mailinabox/mta-sts.txt", "rb") as f:
			mta_sts_policy_id = base64.b64encode(hashlib.sha1(f.read()).digest(), altchars=b"AA").decode("ascii")[0:20]
		mta_sts_records.extend([
			("_mta-sts", "TXT", "v=STSv1; id=" + mta_sts_policy_id, "Optional. Part of the MTA-STS policy for incoming mail. If set, a MTA-STS policy must also be published.")
		])

		# Enable SMTP TLS reporting (https://tools.ietf.org/html/rfc8460) if the user has set a config option.
		# Skip if the rules below if the user has set a custom _smtp._tls record.
		if env.get("MTA_STS_TLSRPT_RUA") and not has_rec("_smtp._tls", "TXT", prefix="v=TLSRPTv1;"):
			mta_sts_records.append(("_smtp._tls", "TXT", "v=TLSRPTv1; rua=" + env["MTA_STS_TLSRPT_RUA"], "Optional. Enables MTA-STS reporting."))
	for qname, rtype, value, explanation in mta_sts_records:
		if not has_rec(qname, rtype):
			records.append((qname, rtype, value, explanation))

	# Add no-mail-here records for any qname that has an A or AAAA record
	# but no MX record. This would include domain itself if domain is a
	# non-mail domain and also may include qnames from custom DNS records.
	# Do this once at the end of generating a zone.
	if is_zone:
		qnames_with_a = {qname for (qname, rtype, value, explanation) in records if rtype in {"A", "AAAA"}}
		qnames_with_mx = {qname for (qname, rtype, value, explanation) in records if rtype == "MX"}
		for qname in qnames_with_a - qnames_with_mx:
			# Mark this domain as not sending mail with hard-fail SPF and DMARC records.
			d = (qname+"." if qname else "") + domain
			if not has_rec(qname, "TXT", prefix="v=spf1 "):
				records.append((qname,  "TXT", 'v=spf1 -all', "Recommended. Prevents use of this domain name for outbound mail by specifying that no servers are valid sources for mail from @%s. If you do send email from this domain name you should either override this record such that the SPF rule does allow the originating server, or, take the recommended approach and have the box handle mail for this domain (simply add any receiving alias at this domain name to make this machine treat the domain name as one of its mail domains)." % d))
			if not has_rec("_dmarc" + ("."+qname if qname else ""), "TXT", prefix="v=DMARC1; "):
				records.append(("_dmarc" + ("."+qname if qname else ""), "TXT", 'v=DMARC1; p=reject;', "Recommended. Prevents use of this domain name for outbound mail by specifying that the SPF rule should be honoured for mail from @%s." % d))

			# And with a null MX record (https://explained-from-first-principles.com/email/#null-mx-record)
			if not has_rec(qname, "MX"):
				records.append((qname, "MX", '0 .', "Recommended. Prevents use of this domain name for incoming mail."))

	# Sort the records. The None records *must* go first in the nsd zone file. Otherwise it doesn't matter.
	records.sort(key = lambda rec : list(reversed(rec[0].split(".")) if rec[0] is not None else ""))

	return records

def is_domain_cert_signed_and_valid(domain, env):
	cert = get_ssl_certificates(env).get(domain)
	if not cert: return False # no certificate provisioned
	cert_status = check_certificate(domain, cert['certificate'], cert['private-key'])
	return cert_status[0] == 'OK'

########################################################################

def build_tlsa_record(env):
	# A DANE TLSA record in DNS specifies that connections on a port
	# must use TLS and the certificate must match a particular criteria.
	#
	# Thanks to http://blog.huque.com/2012/10/dnssec-and-certificates.html
	# and https://community.letsencrypt.org/t/please-avoid-3-0-1-and-3-0-2-dane-tlsa-records-with-le-certificates/7022
	# for explaining all of this! Also see https://tools.ietf.org/html/rfc6698#section-2.1
	# and https://github.com/mail-in-a-box/mailinabox/issues/268#issuecomment-167160243.
	#
	# There are several criteria. We used to use "3 0 1" criteria, which
	# meant to pin a leaf (3) certificate (0) with SHA256 hash (1). But
	# certificates change, and especially as we move to short-lived certs
	# they change often. The TLSA record handily supports the criteria of
	# a leaf certificate (3)'s subject public key (1) with SHA256 hash (1).
	# The subject public key is the public key portion of the private key
	# that generated the CSR that generated the certificate. Since we
	# generate a private key once the first time Mail-in-a-Box is set up
	# and reuse it for all subsequent certificates, the TLSA record will
	# remain valid indefinitely.

	from ssl_certificates import load_cert_chain, load_pem
	from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

	fn = os.path.join(env["STORAGE_ROOT"], "ssl", "ssl_certificate.pem")
	cert = load_pem(load_cert_chain(fn)[0])

	subject_public_key = cert.public_key().public_bytes(Encoding.DER, PublicFormat.SubjectPublicKeyInfo)
	# We could have also loaded ssl_private_key.pem and called priv_key.public_key().public_bytes(...)

	pk_hash = hashlib.sha256(subject_public_key).hexdigest()

	# Specify the TLSA parameters:
	# 3: Match the (leaf) certificate. (No CA, no trust path needed.)
	# 1: Match its subject public key.
	# 1: Use SHA256.
	return "3 1 1 " + pk_hash

def build_sshfp_records():
	# The SSHFP record is a way for us to embed this server's SSH public
	# key fingerprint into the DNS so that remote hosts have an out-of-band
	# method to confirm the fingerprint. See RFC 4255 and RFC 6594. This
	# depends on DNSSEC.
	#
	# On the client side, set SSH's VerifyHostKeyDNS option to 'ask' to
	# include this info in the key verification prompt or 'yes' to trust
	# the SSHFP record.
	#
	# See https://github.com/xelerance/sshfp for inspiriation.

	algorithm_number = {
		"ssh-rsa": 1,
		"ssh-dss": 2,
		"ecdsa-sha2-nistp256": 3,
		"ssh-ed25519": 4,
	}

	# Get our local fingerprints by running ssh-keyscan. The output looks
	# like the known_hosts file: hostname, keytype, fingerprint. The order
	# of the output is arbitrary, so sort it to prevent spurious updates
	# to the zone file (that trigger bumping the serial number). However,
	# if SSH has been configured to listen on a nonstandard port, we must
	# specify that port to sshkeyscan.

	port = get_ssh_port()

	# If nothing returned, SSH is probably not installed.
	if not port:
		return

	keys = shell("check_output", ["ssh-keyscan", "-4", "-t", "rsa,dsa,ecdsa,ed25519", "-p", str(port), "localhost"])
	keys = sorted(keys.split("\n"))

	for key in keys:
		if key.strip() == "" or key[0] == "#": continue
		try:
			_host, keytype, pubkey = key.split(" ")
			yield "%d %d ( %s )" % (
				algorithm_number[keytype],
				2, # specifies we are using SHA-256 on next line
				hashlib.sha256(base64.b64decode(pubkey)).hexdigest().upper(),
				)
		except:
			# Lots of things can go wrong. Don't let it disturb the DNS
			# zone.
			pass

########################################################################

def write_nsd_zone(domain, zonefile, records, env, force):
	# On the $ORIGIN line, there's typically a ';' comment at the end explaining
	# what the $ORIGIN line does. Any further data after the domain confuses
	# ldns-signzone, however. It used to say '; default zone domain'.
	#
	# The SOA contact address for all of the domains on this system is hostmaster
	# @ the PRIMARY_HOSTNAME. Hopefully that's legit.
	#
	# For the refresh through TTL fields, a good reference is:
	# https://www.ripe.net/publications/docs/ripe-203
	#
	# A hash of the available DNSSEC keys are added in a comment so that when
	# the keys change we force a re-generation of the zone which triggers
	# re-signing it.

	zone = """
$ORIGIN {domain}.
$TTL 86400          ; default time to live

@ IN SOA ns1.{primary_domain}. hostmaster.{primary_domain}. (
           __SERIAL__     ; serial number
           7200     ; Refresh (secondary nameserver update interval)
           3600     ; Retry (when refresh fails, how often to try again, should be lower than the refresh)
           1209600  ; Expire (when refresh fails, how long secondary nameserver will keep records around anyway)
           86400    ; Negative TTL (how long negative responses are cached)
           )
"""

	# Replace replacement strings.
	zone = zone.format(domain=domain, primary_domain=env["PRIMARY_HOSTNAME"])

	# Add records.
	for subdomain, querytype, value, _explanation in records:
		if subdomain:
			zone += subdomain
		zone += "\tIN\t" + querytype + "\t"
		if querytype == "TXT":
			# Divide into 255-byte max substrings.
			v2 = ""
			while len(value) > 0:
				s = value[0:255]
				value = value[255:]
				s = s.replace('\\', '\\\\') # escape backslashes
				s = s.replace('"', '\\"') # escape quotes
				s = '"' + s + '"' # wrap in quotes
				v2 += s + " "
			value = v2
		zone += value + "\n"

	# Append a stable hash of DNSSEC signing keys in a comment.
	zone += f"\n; DNSSEC signing keys hash: {hash_dnssec_keys(domain, env)}\n"

	# DNSSEC requires re-signing a zone periodically. That requires
	# bumping the serial number even if no other records have changed.
	# We don't see the DNSSEC records yet, so we have to figure out
	# if a re-signing is necessary so we can prematurely bump the
	# serial number.
	force_bump = False
	if not os.path.exists(zonefile + ".signed"):
		# No signed file yet. Shouldn't normally happen unless a box
		# is going from not using DNSSEC to using DNSSEC.
		force_bump = True
	else:
		# We've signed the domain. Check if we are close to the expiration
		# time of the signature. If so, we'll force a bump of the serial
		# number so we can re-sign it.
		with open(zonefile + ".signed", encoding="utf-8") as f:
			signed_zone = f.read()
		expiration_times = re.findall(r"\sRRSIG\s+SOA\s+\d+\s+\d+\s\d+\s+(\d{14})", signed_zone)
		if len(expiration_times) == 0:
			# weird
			force_bump = True
		else:
			# All of the times should be the same, but if not choose the soonest.
			expiration_time = min(expiration_times)
			expiration_time = datetime.datetime.strptime(expiration_time, "%Y%m%d%H%M%S")
			if expiration_time - datetime.datetime.now() < datetime.timedelta(days=3):
				# We're within three days of the expiration, so bump serial & resign.
				force_bump = True

	# Set the serial number.
	serial = datetime.datetime.now().strftime("%Y%m%d00")
	if os.path.exists(zonefile):
		# If the zone already exists, is different, and has a later serial number,
		# increment the number.
		with open(zonefile, encoding="utf-8") as f:
			existing_zone = f.read()
			m = re.search(r"(\d+)\s*;\s*serial number", existing_zone)
			if m:
				# Clear out the serial number in the existing zone file for the
				# purposes of seeing if anything *else* in the zone has changed.
				existing_serial = m.group(1)
				existing_zone = existing_zone.replace(m.group(0), "__SERIAL__     ; serial number")

				# If the existing zone is the same as the new zone (modulo the serial number),
				# there is no need to update the file. Unless we're forcing a bump.
				if zone == existing_zone and not force_bump and not force:
					return False

				# If the existing serial is not less than a serial number
				# based on the current date plus 00, increment it. Otherwise,
				# the serial number is less than our desired new serial number
				# so we'll use the desired new number.
				if existing_serial >= serial:
					serial = str(int(existing_serial) + 1)

	zone = zone.replace("__SERIAL__", serial)

	# Write the zone file.
	with open(zonefile, "w", encoding="utf-8") as f:
		f.write(zone)

	return True # file is updated

def get_dns_zonefile(zone, env):
	for domain, fn in get_dns_zones(env):
		if zone == domain:
			break
	else:
		raise ValueError("%s is not a domain name that corresponds to a zone." % zone)

	nsd_zonefile = "/etc/nsd/zones/" + fn
	with open(nsd_zonefile, encoding="utf-8") as f:
		return f.read()

########################################################################

def write_nsd_conf(zonefiles, additional_records, env):
	# Write the list of zones to a configuration file.
	nsd_conf_file = "/etc/nsd/nsd.conf.d/zones.conf"
	nsdconf = ""

	# Append the zones.
	for domain, zonefile in zonefiles:
		nsdconf += f"""
zone:
	name: {domain}
	zonefile: {zonefile}
"""

		# If custom secondary nameservers have been set, allow zone transfers
		# and, if not a subnet, notifies to them.
		for ipaddr in get_secondary_dns(additional_records, mode="xfr"):
			if "/" not in ipaddr:
				nsdconf += "\n\tnotify: %s NOKEY" % (ipaddr)
			nsdconf += "\n\tprovide-xfr: %s NOKEY\n" % (ipaddr)

	# Check if the file is changing. If it isn't changing,
	# return False to flag that no change was made.
	if os.path.exists(nsd_conf_file):
		with open(nsd_conf_file, encoding="utf-8") as f:
			if f.read() == nsdconf:
				return False

	# Write out new contents and return True to signal that
	# configuration changed.
	with open(nsd_conf_file, "w", encoding="utf-8") as f:
		f.write(nsdconf)
	return True

########################################################################

def find_dnssec_signing_keys(domain, env):
	# For key that we generated (one per algorithm)...
	d = os.path.join(env['STORAGE_ROOT'], 'dns/dnssec')
	keyconfs = [f for f in os.listdir(d) if f.endswith(".conf")]
	for keyconf in keyconfs:
		# Load the file holding the KSK and ZSK key filenames.
		keyconf_fn = os.path.join(d, keyconf)
		keyinfo = load_env_vars_from_file(keyconf_fn)

		# Skip this key if the conf file has a setting named DOMAINS,
		# holding a comma-separated list of domain names, and if this
		# domain is not in the list. This allows easily disabling a
		# key by setting "DOMAINS=" or "DOMAINS=none", other than
		# deleting the key's .conf file, which might result in the key
		# being regenerated next upgrade. Keys should be disabled if
		# they are not needed to reduce the DNSSEC query response size.
		if "DOMAINS" in keyinfo and domain not in [dd.strip() for dd in keyinfo["DOMAINS"].split(",")]:
			continue

		for keytype in ("KSK", "ZSK"):
			yield keytype, keyinfo[keytype]

def hash_dnssec_keys(domain, env):
	# Create a stable (by sorting the items) hash of all of the private keys
	# that will be used to sign this domain.
	keydata = []
	for keytype, keyfn in sorted(find_dnssec_signing_keys(domain, env)):
		oldkeyfn = os.path.join(env['STORAGE_ROOT'], 'dns/dnssec', keyfn + ".private")
		keydata.extend((keytype, keyfn))
		with open(oldkeyfn, encoding="utf-8") as fr:
			keydata.append( fr.read() )
	keydata = "".join(keydata).encode("utf8")
	return hashlib.sha1(keydata).hexdigest()

def sign_zone(domain, zonefile, env):
	# Sign the zone with all of the keys that were generated during
	# setup so that the user can choose which to use in their DS record at
	# their registrar, and also to support migration to newer algorithms.

	# In order to use the key files generated at setup which are for
	# the domain _domain_, we have to re-write the files and place
	# the actual domain name in it, so that ldns-signzone works.
	#
	# Patch each key, storing the patched version in /tmp for now.
	# Each key has a .key and .private file. Collect a list of filenames
	# for all of the keys (and separately just the key-signing keys).
	all_keys = []
	ksk_keys = []
	for keytype, keyfn in find_dnssec_signing_keys(domain, env):
		newkeyfn = '/tmp/' + keyfn.replace("_domain_", domain)

		for ext in (".private", ".key"):
			# Copy the .key and .private files to /tmp to patch them up.
			#
			# Use os.umask and open().write() to securely create a copy that only
			# we (root) can read.
			oldkeyfn = os.path.join(env['STORAGE_ROOT'], 'dns/dnssec', keyfn + ext)
			with open(oldkeyfn, encoding="utf-8") as fr:
				keydata = fr.read()
			keydata = keydata.replace("_domain_", domain)
			prev_umask = os.umask(0o77) # ensure written file is not world-readable
			try:
				with open(newkeyfn + ext, "w", encoding="utf-8") as fw:
					fw.write(keydata)
			finally:
				os.umask(prev_umask) # other files we write should be world-readable

		# Put the patched key filename base (without extension) into the list of keys we'll sign with.
		all_keys.append(newkeyfn)
		if keytype == "KSK": ksk_keys.append(newkeyfn)

	# Do the signing.
	expiry_date = (datetime.datetime.now() + datetime.timedelta(days=30)).strftime("%Y%m%d")
	shell('check_call', ["/usr/bin/ldns-signzone",
		# expire the zone after 30 days
		"-e", expiry_date,

		# use NSEC3
		"-n",

		# zonefile to sign
		"/etc/nsd/zones/" + zonefile,
	]
		# keys to sign with (order doesn't matter -- it'll figure it out)
		+ all_keys
	)

	# Create a DS record based on the patched-up key files. The DS record is specific to the
	# zone being signed, so we can't use the .ds files generated when we created the keys.
	# The DS record points to the KSK only. Write this next to the zone file so we can
	# get it later to give to the user with instructions on what to do with it.
	#
	# Generate a DS record for each key. There are also several possible hash algorithms that may
	# be used, so we'll pre-generate all for each key. One DS record per line. Only one
	# needs to actually be deployed at the registrar. We'll select the preferred one
	# in the status checks.
	with open("/etc/nsd/zones/" + zonefile + ".ds", "w", encoding="utf-8") as f:
		for key in ksk_keys:
			for digest_type in ('1', '2', '4'):
				rr_ds = shell('check_output', ["/usr/bin/ldns-key2ds",
					"-n", # output to stdout
					"-" + digest_type, # 1=SHA1, 2=SHA256, 4=SHA384
					key + ".key"
				])
				f.write(rr_ds)

	# Remove the temporary patched key files.
	for fn in all_keys:
		os.unlink(fn + ".private")
		os.unlink(fn + ".key")

########################################################################

def write_opendkim_tables(domains, env):
	# Append a record to OpenDKIM's KeyTable and SigningTable for each domain
	# that we send mail from (zones and all subdomains).

	opendkim_key_file = os.path.join(env['STORAGE_ROOT'], 'mail/dkim/mail.private')

	if not os.path.exists(opendkim_key_file):
		# Looks like OpenDKIM is not installed.
		return False

	config = {
		# The SigningTable maps email addresses to a key in the KeyTable that
		# specifies signing information for matching email addresses. Here we
		# map each domain to a same-named key.
		#
		# Elsewhere we set the DMARC policy for each domain such that mail claiming
		# to be From: the domain must be signed with a DKIM key on the same domain.
		# So we must have a separate KeyTable entry for each domain.
		"SigningTable":
			"".join(
				f"*@{domain} {domain}\n"
				for domain in domains
			),

		# The KeyTable specifies the signing domain, the DKIM selector, and the
		# path to the private key to use for signing some mail. Per DMARC, the
		# signing domain must match the sender's From: domain.
		"KeyTable":
			"".join(
				f"{domain} {domain}:mail:{opendkim_key_file}\n"
				for domain in domains
			),
	}

	did_update = False
	for filename, content in config.items():
		# Don't write the file if it doesn't need an update.
		if os.path.exists("/etc/opendkim/" + filename):
			with open("/etc/opendkim/" + filename, encoding="utf-8") as f:
				if f.read() == content:
					continue

		# The contents needs to change.
		with open("/etc/opendkim/" + filename, "w", encoding="utf-8") as f:
			f.write(content)
		did_update = True

	# Return whether the files changed. If they didn't change, there's
	# no need to kick the opendkim process.
	return did_update

########################################################################

def get_custom_dns_config(env, only_real_records=False):
	try:
		with open(os.path.join(env['STORAGE_ROOT'], 'dns/custom.yaml'), encoding="utf-8") as f:
			custom_dns = rtyaml.load(f)
		if not isinstance(custom_dns, dict): raise ValueError # caught below
	except:
		return [ ]

	for qname, value in custom_dns.items():
		if qname == "_secondary_nameserver" and only_real_records: continue # skip fake record

		# Short form. Mapping a domain name to a string is short-hand
		# for creating A records.
		if isinstance(value, str):
			values = [("A", value)]

		# A mapping creates multiple records.
		elif isinstance(value, dict):
			values = value.items()

		# No other type of data is allowed.
		else:
			raise ValueError

		for rtype, value2 in values:
			if isinstance(value2, str):
				yield (qname, rtype, value2)
			elif isinstance(value2, list):
				for value3 in value2:
					yield (qname, rtype, value3)
			# No other type of data is allowed.
			else:
				raise ValueError

def filter_custom_records(domain, custom_dns_iter):
	for qname, rtype, value in custom_dns_iter:
		# We don't count the secondary nameserver config (if present) as a record - that would just be
		# confusing to users. Instead it is accessed/manipulated directly via (get/set)_custom_dns_config.
		if qname == "_secondary_nameserver": continue

		# Is this record for the domain or one of its subdomains?
		# If `domain` is None, return records for all domains.
		if domain is not None and qname != domain and not qname.endswith("." + domain): continue

		# Turn the fully qualified domain name in the YAML file into
		# our short form (None => domain, or a relative QNAME) if
		# domain is not None.
		if domain is not None:
			qname = None if qname == domain else qname[0:len(qname) - len("." + domain)]

		yield (qname, rtype, value)

def write_custom_dns_config(config, env):
	# We get a list of (qname, rtype, value) triples. Convert this into a
	# nice dictionary format for storage on disk.
	from collections import OrderedDict
	config = list(config)
	dns = OrderedDict()
	seen_qnames = set()

	# Process the qnames in the order we see them.
	for qname in [rec[0] for rec in config]:
		if qname in seen_qnames: continue
		seen_qnames.add(qname)

		records = [(rec[1], rec[2]) for rec in config if rec[0] == qname]
		if len(records) == 1 and records[0][0] == "A":
			dns[qname] = records[0][1]
		else:
			dns[qname] = OrderedDict()
			seen_rtypes = set()

			# Process the rtypes in the order we see them.
			for rtype in [rec[0] for rec in records]:
				if rtype in seen_rtypes: continue
				seen_rtypes.add(rtype)

				values = [rec[1] for rec in records if rec[0] == rtype]
				if len(values) == 1:
					values = values[0]
				dns[qname][rtype] = values

	# Write.
	config_yaml = rtyaml.dump(dns)
	with open(os.path.join(env['STORAGE_ROOT'], 'dns/custom.yaml'), "w", encoding="utf-8") as f:
		f.write(config_yaml)

def set_custom_dns_record(qname, rtype, value, action, env):
	# validate qname
	for zone, _fn in get_dns_zones(env):
		# It must match a zone apex or be a subdomain of a zone
		# that we are otherwise hosting.
		if qname == zone or qname.endswith("."+zone):
			break
	else:
		# No match.
		if qname != "_secondary_nameserver":
			raise ValueError("%s is not a domain name or a subdomain of a domain name managed by this box." % qname)

	# validate rtype
	rtype = rtype.upper()
	if value is not None and qname != "_secondary_nameserver":
		if not re.search(DOMAIN_RE, qname):
			msg = "Invalid name."
			raise ValueError(msg)

		if rtype in {"A", "AAAA"}:
			if value != "local": # "local" is a special flag for us
				v = ipaddress.ip_address(value) # raises a ValueError if there's a problem
				if rtype == "A" and not isinstance(v, ipaddress.IPv4Address): raise ValueError("That's an IPv6 address.")
				if rtype == "AAAA" and not isinstance(v, ipaddress.IPv6Address): raise ValueError("That's an IPv4 address.")
		elif rtype in {"CNAME", "NS"}:
			if rtype == "NS" and qname == zone:
				msg = "NS records can only be set for subdomains."
				raise ValueError(msg)

			# ensure value has a trailing dot
			if not value.endswith("."):
				value = value + "."

			if not re.search(DOMAIN_RE, value):
				msg = "Invalid value."
				raise ValueError(msg)
		elif rtype in {"CNAME", "TXT", "SRV", "MX", "SSHFP", "CAA"}:
			# anything goes
			pass
		else:
			raise ValueError("Unknown record type '%s'." % rtype)

	# load existing config
	config = list(get_custom_dns_config(env))

	# update
	newconfig = []
	made_change = False
	needs_add = True
	for _qname, _rtype, _value in config:
		if action == "add":
			if (_qname, _rtype, _value) == (qname, rtype, value):
				# Record already exists. Bail.
				return False
		elif action == "set":
			if (_qname, _rtype) == (qname, rtype):
				if _value == value:
					# Flag that the record already exists, don't
					# need to add it.
					needs_add = False
				else:
					# Drop any other values for this (qname, rtype).
					made_change = True
					continue
		elif action == "remove":
			if (_qname, _rtype, _value) == (qname, rtype, value):
				# Drop this record.
				made_change = True
				continue
			if value is None and (_qname, _rtype) == (qname, rtype):
				# Drop all qname-rtype records.
				made_change = True
				continue
		else:
			raise ValueError("Invalid action: " + action)

		# Preserve this record.
		newconfig.append((_qname, _rtype, _value))

	if action in {"add", "set"} and needs_add and value is not None:
		newconfig.append((qname, rtype, value))
		made_change = True

	if made_change:
		# serialize & save
		write_custom_dns_config(newconfig, env)
	return made_change

########################################################################

def get_secondary_dns(custom_dns, mode=None):
	resolver = dns.resolver.get_default_resolver()
	resolver.timeout = 10
	resolver.lifetime = 10

	values = []
	for qname, _rtype, value in custom_dns:
		if qname != '_secondary_nameserver': continue
		for hostname in value.split(" "):
			hostname = hostname.strip()
			if mode is None:
				# Just return the setting.
				values.append(hostname)
				continue

			# If the entry starts with "xfr:" only include it in the zone transfer settings.
			if hostname.startswith("xfr:"):
				if mode != "xfr": continue
				hostname = hostname[4:]

			# If is a hostname, before including in zone xfr lines,
			# resolve to an IP address.
			# It may not resolve to IPv6, so don't throw an exception if it
			# doesn't. Skip the entry if there is a DNS error.
			if mode == "xfr":
				try:
					ipaddress.ip_interface(hostname) # test if it's an IP address or CIDR notation
					values.append(hostname)
				except ValueError:
					try:
						response = dns.resolver.resolve(hostname+'.', "A", raise_on_no_answer=False)
						values.extend(map(str, response))
					except dns.exception.DNSException:
						pass
					try:
						response = dns.resolver.resolve(hostname+'.', "AAAA", raise_on_no_answer=False)
						values.extend(map(str, response))
					except dns.exception.DNSException:
						pass

			else:
				values.append(hostname)

	return values

def set_secondary_dns(hostnames, env):
	if len(hostnames) > 0:
		# Validate that all hostnames are valid and that all zone-xfer IP addresses are valid.
		resolver = dns.resolver.get_default_resolver()
		resolver.timeout = 5
		resolver.lifetime = 5

		for item in hostnames:
			if not item.startswith("xfr:"):
				# Resolve hostname.
				try:
					resolver.resolve(item, "A")
				except (dns.resolver.NoNameservers, dns.resolver.NXDOMAIN, dns.resolver.NoAnswer, dns.resolver.Timeout):
					try:
						resolver.resolve(item, "AAAA")
					except (dns.resolver.NoNameservers, dns.resolver.NXDOMAIN, dns.resolver.NoAnswer, dns.resolver.Timeout):
						raise ValueError("Could not resolve the IP address of %s." % item)
			else:
				# Validate IP address.
				try:
					if "/" in item[4:]:
						ipaddress.ip_network(item[4:]) # raises a ValueError if there's a problem
					else:
						ipaddress.ip_address(item[4:]) # raises a ValueError if there's a problem
				except ValueError:
					raise ValueError("'%s' is not an IPv4 or IPv6 address or subnet." % item[4:])

		# Set.
		set_custom_dns_record("_secondary_nameserver", "A", " ".join(hostnames), "set", env)
	else:
		# Clear.
		set_custom_dns_record("_secondary_nameserver", "A", None, "set", env)

	# Apply.
	return do_dns_update(env)


def get_custom_dns_records(custom_dns, qname, rtype):
	for qname1, rtype1, value in custom_dns:
		if qname1 == qname and rtype1 == rtype:
			yield value

########################################################################

def build_recommended_dns(env):
	ret = []
	for (domain, _zonefile, records) in build_zones(env):
		# remove records that we don't display
		records = [r for r in records if r[3] is not False]

		# put Required at the top, then Recommended, then everythiing else
		records.sort(key = lambda r : 0 if r[3].startswith("Required.") else (1 if r[3].startswith("Recommended.") else 2))

		# expand qnames
		for i in range(len(records)):
			qname = domain if records[i][0] is None else records[i][0] + "." + domain

			records[i] = {
				"qname": qname,
				"rtype": records[i][1],
				"value": records[i][2],
				"explanation": records[i][3],
			}

		# return
		ret.append((domain, records))
	return ret

if __name__ == "__main__":
	from utils import load_environment
	env = load_environment()
	if sys.argv[-1] == "--lint":
		write_custom_dns_config(get_custom_dns_config(env), env)
	else:
		for _zone, records in build_recommended_dns(env):
			for record in records:
				print("; " + record['explanation'])
				print(record['qname'], record['rtype'], record['value'], sep="\t")
				print()
