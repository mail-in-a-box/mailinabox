#!/usr/bin/python3

# Runs SSLyze on the TLS endpoints of a box and outputs
# the results so we can inspect the settings and compare
# against a known good version in tls_results.txt.
#
# Make sure you have SSLyze available:
# wget https://github.com/nabla-c0d3/sslyze/releases/download/release-0.11/sslyze-0_11-linux64.zip
# unzip sslyze-0_11-linux64.zip
#
# Then run:
#
# python3 tls.py yourservername
#
# If you are on a residential network that blocks outbound
# port 25 connections, then you can proxy the connections
# through some other host you can ssh into (maybe the box
# itself?):
#
# python3 --proxy user@ssh_host yourservername
#
# (This will launch "ssh -N -L10023:yourservername:testport user@ssh_host"
# to create a tunnel.)

import sys, subprocess, re, time, json, csv, io, urllib.request

######################################################################

# PARSE COMMAND LINE

proxy = None
args = list(sys.argv[1:])
while len(args) > 0:
	if args[0] == "--proxy":
		args.pop(0)
		proxy = args.pop(0)
	break

if len(args) == 0:
	print("Usage: python3 tls.py [--proxy ssh_host] hostname")
	sys.exit(0)

host = args[0]

######################################################################

SSLYZE = "sslyze-0_11-linux64/sslyze/sslyze.py"

common_opts = ["--sslv2", "--sslv3", "--tlsv1", "--tlsv1_1", "--tlsv1_2", "--reneg", "--resum",
	"--hide_rejected_ciphers", "--compression", "--heartbleed"]

# Recommendations from Mozilla as of May 20, 2015 at
# https://wiki.mozilla.org/Security/Server_Side_TLS.
#
# The 'modern' ciphers support Firefox 27, Chrome 22, IE 11,
# Opera 14, Safari 7, Android 4.4, Java 8. Assumes TLSv1.1,
# TLSv1.2 only, though we may also be allowing TLSv3.
#
# The 'intermediate' ciphers support Firefox 1, Chrome 1, IE 7,
# Opera 5, Safari 1, Windows XP IE8, Android 2.3, Java 7.
# Assumes TLSv1, TLSv1.1, TLSv1.2.
#
# The 'old' ciphers bring compatibility back to Win XP IE 6.
MOZILLA_CIPHERS_MODERN = "ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256"
MOZILLA_CIPHERS_INTERMEDIATE = "ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA:ECDHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-RSA-AES256-SHA256:DHE-RSA-AES256-SHA:ECDHE-ECDSA-DES-CBC3-SHA:ECDHE-RSA-DES-CBC3-SHA:EDH-RSA-DES-CBC3-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:DES-CBC3-SHA:!DSS"
MOZILLA_CIPHERS_OLD = "ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-DSS-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA:DHE-RSA-AES256-SHA:ECDHE-RSA-DES-CBC3-SHA:ECDHE-ECDSA-DES-CBC3-SHA:EDH-RSA-DES-CBC3-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:AES:DES-CBC3-SHA:HIGH:SEED:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!MD5:!PSK:!RSAPSK:!aDH:!aECDH:!EDH-DSS-DES-CBC3-SHA:!KRB5-DES-CBC3-SHA:!SRP"

######################################################################

def sslyze(opts, port, ok_ciphers):
	# Print header.
	header = ("PORT %d" % port)
	print(header)
	print("-" * (len(header)))

	# What ciphers should we expect?
	ok_ciphers = subprocess.check_output(["openssl", "ciphers", ok_ciphers]).decode("utf8").strip().split(":")

	# Form the SSLyze connection string.
	connection_string = host + ":" + str(port)

	# Proxy via SSH.
	proxy_proc = None
	if proxy:
		connection_string = "localhost:10023"
		proxy_proc = subprocess.Popen(["ssh", "-N", "-L10023:%s:%d" % (host, port), proxy])
		time.sleep(3)

	try:
		# Execute SSLyze.
		out = subprocess.check_output([SSLYZE] + common_opts + opts + [connection_string])
		out = out.decode("utf8")

		# Trim output to make better for storing in git.
		if "SCAN RESULTS FOR" not in out:
			# Failed. Just output the error.
			out = re.sub("[\w\W]*CHECKING HOST\(S\) AVAILABILITY\n\s*-+\n", "", out) # chop off header that shows the host we queried
		out = re.sub("[\w\W]*SCAN RESULTS FOR.*\n\s*-+\n", "", out) # chop off header that shows the host we queried
		out = re.sub("SCAN COMPLETED IN .*", "", out)
		out = out.rstrip(" \n-") + "\n"

		# Print.
		print(out)

		# Pull out the accepted ciphers list for each SSL/TLS protocol
		# version outputted.
		accepted_ciphers = set()
		for ciphers in re.findall(" Accepted:([\w\W]*?)\n *\n", out):
			accepted_ciphers |= set(re.findall("\n\s*(\S*)", ciphers))

		# Compare to what Mozilla recommends, for a given modernness-level.
		print("  Should Not Offer: " + (", ".join(sorted(accepted_ciphers-set(ok_ciphers))) or "(none -- good)"))
		print("  Could Also Offer: " + (", ".join(sorted(set(ok_ciphers)-accepted_ciphers)) or "(none -- good)"))

		# What clients does that mean we support on this protocol?
		supported_clients = { }
		for cipher in accepted_ciphers:
			if cipher in cipher_clients:
				for client in cipher_clients[cipher]:
					supported_clients[client] = supported_clients.get(client, 0) + 1
		print("  Supported Clients: " + (", ".join(sorted(supported_clients.keys(), key = lambda client : -supported_clients[client]))))

		# Blank line.
		print()

	finally:
		if proxy_proc:
			proxy_proc.terminate()
			try:
				proxy_proc.wait(5)
			except subprocess.TimeoutExpired:
				proxy_proc.kill()

# Get a list of OpenSSL cipher names.
cipher_names = { }
for cipher in csv.DictReader(io.StringIO(urllib.request.urlopen("https://raw.githubusercontent.com/mail-in-a-box/user-agent-tls-capabilities/master/cipher_names.csv").read().decode("utf8"))):
	# not sure why there are some multi-line values, use first line:
	cipher["OpenSSL"] = cipher["OpenSSL"].split("\n")[0]
	cipher_names[cipher["IANA"]] = cipher["OpenSSL"]

# Get a list of what clients support what ciphers, using OpenSSL cipher names.
client_compatibility = json.loads(urllib.request.urlopen("https://raw.githubusercontent.com/mail-in-a-box/user-agent-tls-capabilities/master/clients.json").read().decode("utf8"))
cipher_clients = { }
for client in client_compatibility:
	if len(set(client['protocols']) & set(["TLS 1.0", "TLS 1.1", "TLS 1.2"])) == 0: continue # does not support TLS
	for cipher in client['ciphers']:
		cipher_clients.setdefault(cipher_names.get(cipher), set()).add("/".join(x for x in [client['client']['name'], client['client']['version'], client['client']['platform']] if x))

# Run SSLyze on various ports.

# SMTP
sslyze(["--starttls=smtp"], 25, MOZILLA_CIPHERS_OLD)

# SMTP Submission
sslyze(["--starttls=smtp"], 587, MOZILLA_CIPHERS_MODERN)

# HTTPS
sslyze(["--http_get", "--chrome_sha1", "--hsts"], 443, MOZILLA_CIPHERS_INTERMEDIATE)

# IMAP
sslyze([], 993, MOZILLA_CIPHERS_MODERN)

# POP3
sslyze([], 995, MOZILLA_CIPHERS_MODERN)
