#!/usr/bin/python3
# Test DNS configuration.
#
# tests/dns.py ipaddr hostname

import sys, subprocess, re, difflib

if len(sys.argv) < 3:
	print("Usage: tests/dns.py ipaddress hostname")
	sys.exit(1)

ipaddr, hostname = sys.argv[1:]

def dig(digargs):
	# run dig and clean the output
	response = subprocess.check_output(['dig', '@' + ipaddr] + digargs).decode('utf8')
	response = re.sub('[\r\n]+', '\n', response) # remove blank lines
	response = re.sub('\n;.*', '', response) # remove comments
	response = response.strip() + "\n"
	return response

# call dig a few times with different parameters
digoutput = \
   dig([hostname])\
 + dig(["www." + hostname, "+noadditional", "+noauthority"]) \
 + dig(["mx", hostname, "+noadditional", "+noauthority"]) \
 + dig(["txt", hostname, "+noadditional", "+noauthority"]) \
 + dig(["txt", "mail._domainkey." + hostname, "+noadditional", "+noauthority"])

# normalize DKIM key
digoutput = re.sub(r"(\"p=).*(\")", r"\1__KEY__\2", digoutput)

# construct the expected output
subs = { "ipaddr": ipaddr, "hostname": hostname }
expected = """
{hostname}.	86400	IN	A	{ipaddr}
{hostname}.	86400	IN	NS	ns1.{hostname}.
{hostname}.	86400	IN	NS	ns2.{hostname}.
ns1.{hostname}.	86400	IN	A	{ipaddr}
ns2.{hostname}.	86400	IN	A	{ipaddr}
www.{hostname}.	86400	IN	A	{ipaddr}
{hostname}.	86400	IN	MX	10 {hostname}.
{hostname}.	300	IN	TXT	"v=spf1 mx -all"
mail._domainkey.{hostname}. 86400 IN TXT	"v=DKIM1\; k=rsa\; s=email\; " "p=__KEY__"
""".format(**subs).strip() + "\n"

# Show a diff if there are any changes
has_diff = False
def split(s): return [line+"\n" for line in s.split("\n")]
for line in difflib.unified_diff(split(expected), split(digoutput), fromfile='expected DNS settings', tofile='output from dig'):
	sys.stdout.write(line)   
	has_diff = True

if not has_diff:
	print("DNS is OK.")
	sys.exit(0)

sys.exit(1)
