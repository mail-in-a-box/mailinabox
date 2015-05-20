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

import sys, subprocess, re, time

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

######################################################################

def sslyze(opts, port):
	# Print header.
	header = ("PORT %d" % port)
	print(header)
	print("-" * (len(header)))

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
	finally:
		if proxy_proc:
			proxy_proc.terminate()
			try:
				proxy_proc.wait(5)
			except TimeoutExpired:
				proxy_proc.kill()

# Run SSLyze on various ports.

# SMTP
sslyze(["--starttls=smtp"], 25)

# SMTP Submission
sslyze(["--starttls=smtp"], 587)

# HTTPS
sslyze(["--http_get", "--chrome_sha1", "--hsts"], 443)

# IMAP
sslyze([], 993)

# POP3
sslyze([], 995)
