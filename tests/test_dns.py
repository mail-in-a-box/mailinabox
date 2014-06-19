#!/usr/bin/env python3
#
# Tests the DNS configuration of a Mail-in-a-Box.
#
# tests/dns.py ipaddr hostname
#
# where ipaddr is the IP address of your Mail-in-a-Box
# and hostname is the domain name to check the DNS for.

import sys, re, difflib
import dns.reversename, dns.resolver

if len(sys.argv) < 3:
	print("Usage: tests/dns.py ipaddress hostname [primary hostname]")
	sys.exit(1)

ipaddr, hostname = sys.argv[1:3]
primary_hostname = hostname
if len(sys.argv) == 4:
	primary_hostname = sys.argv[3]

def test(server, description):
	tests = [
		(hostname, "A", ipaddr),
		#(hostname, "NS", "ns1.%s.;ns2.%s." % (primary_hostname, primary_hostname)),
		("ns1." + primary_hostname, "A", ipaddr),
		("ns2." + primary_hostname, "A", ipaddr),
		("www." + hostname, "A", ipaddr),
		(hostname, "MX", "10 " + primary_hostname + "."),
		(hostname, "TXT", "\"v=spf1 mx -all\""),
		("mail._domainkey." + hostname, "TXT", "\"v=DKIM1; k=rsa; s=email; \" \"p=__KEY__\""),
		#("_adsp._domainkey." + hostname, "TXT", "\"dkim=all\""),
		("_dmarc." + hostname, "TXT", "\"v=DMARC1; p=quarantine\""),
	]
	return test2(tests, server, description)

def test_ptr(server, description):
	ipaddr_rev = dns.reversename.from_address(ipaddr)
	tests = [
		(ipaddr_rev, "PTR", hostname+'.'),
	]
	return test2(tests, server, description)

def test2(tests, server, description):
	first = True
	resolver = dns.resolver.get_default_resolver()
	resolver.nameservers = [server]
	for qname, rtype, expected_answer in tests:
		# do the query and format the result as a string
		try:
			response = dns.resolver.query(qname, rtype)
		except dns.resolver.NoNameservers:
			# host did not have an answer for this query
			print("Could not connect to %s for DNS query." % server)
			sys.exit(1)
		except (dns.resolver.NXDOMAIN, dns.resolver.NoAnswer):
			# host did not have an answer for this query; not sure what the
			# difference is between the two exceptions
			response = ["[no value]"]
		response = ";".join(str(r) for r in response)
		response = re.sub(r"(\"p=).*(\")", r"\1__KEY__\2", response) # normalize DKIM key
		response = response.replace("\"\" ", "") # normalize TXT records (DNSSEC signing inserts empty text string components)

		# is it right?
		if response == expected_answer:
			#print(server, ":", qname, rtype, "?", response)
			continue

		# show prolem
		if first:
			print("Incorrect DNS Response from", description)
			print()
			print("QUERY               ", "RESPONSE    ", "CORRECT VALUE", sep='\t')
			first = False

		print((qname + "/" + rtype).ljust(20), response.ljust(12), expected_answer, sep='\t')
	return first # success

# Test the response from the machine itself.
if not test(ipaddr, "Mail-in-a-Box"):
	print ()
	print ("Please run the Mail-in-a-Box setup script on %s again." % hostname)
	sys.exit(1)
else:
	print ("The Mail-in-a-Box provided correct DNS answers.")
	print ()

	# If those settings are OK, also test Google's Public DNS
	# to see if the machine is hooked up to recursive DNS properly.
	if not test("8.8.8.8", "Google Public DNS"):
		print ()
		print ("Check that the nameserver settings for %s are correct at your domain registrar. It may take a few hours for Google Public DNS to update after changes on your Mail-in-a-Box." % hostname)
		sys.exit(1)
	else:
		print ("Your domain registrar or DNS host appears to be configured correctly as well. Public DNS provides the same answers.")
		print ()

		# And if that's OK, also check reverse DNS (the PTR record).
		if not test_ptr("8.8.8.8", "Google Public DNS (Reverse DNS)"):
			print ()
			print ("The reverse DNS for %s is not correct. Consult your ISP for how to set the reverse DNS (also called the PTR record) for %s to %s." % (hostname, hostname, ipaddr))
			sys.exit(1)
		else:
			print ("And the reverse DNS for the domain is correct.")
			print ()
			print ("DNS is OK.")
