# Test that a box's fail2ban setting are working
# correctly by attempting a bunch of failed logins.
#
# Specify a SSH login command (which we use to reset
# fail2ban after each test) and the hostname to
# try to log in to.
######################################################################

import sys, os, time, functools

# parse command line

if len(sys.argv) != 3:
	print("Usage: tests/fail2ban.py \"ssh user@hostname\" hostname")
	sys.exit(1)

ssh_command, hostname = sys.argv[1:3]

# define some test types

import socket
socket.setdefaulttimeout(10)

class IsBlocked(Exception):
	"""Tests raise this exception when it appears that a fail2ban
	jail is in effect, i.e. on a connection refused error."""
	pass

def smtp_test():
	import smtplib

	try:
		server = smtplib.SMTP(hostname, 587)
	except ConnectionRefusedError:
		# looks like fail2ban worked
		raise IsBlocked()
	server.starttls()
	server.ehlo_or_helo_if_needed()

	try:
		server.login("fakeuser", "fakepassword")
		raise Exception("authentication didn't fail")
	except smtplib.SMTPAuthenticationError:
		# athentication should fail
		pass

	try:
		server.quit()
	except:
		# ignore errors here
		pass

def imap_test():
	import imaplib

	try:
		M = imaplib.IMAP4_SSL(hostname)
	except ConnectionRefusedError:
		# looks like fail2ban worked
		raise IsBlocked()

	try:
		M.login("fakeuser", "fakepassword")
		raise Exception("authentication didn't fail")
	except imaplib.IMAP4.error:
		# authentication should fail
		pass
	finally:
		M.logout() # shuts down connection, has nothing to do with login()

def http_test(url, expected_status, postdata=None, qsargs=None, auth=None):
	import urllib.parse
	import requests
	from requests.auth import HTTPBasicAuth

	# form request
	url = urllib.parse.urljoin("https://" + hostname, url)
	if qsargs: url += "?" + urllib.parse.urlencode(qsargs)
	urlopen = requests.get if not postdata else requests.post

	try:
		# issue request
		r = urlopen(
			url,
			auth=HTTPBasicAuth(*auth) if auth else None,
			data=postdata,
			headers={'User-Agent': 'Mail-in-a-Box fail2ban tester'},
			timeout=8,
			verify=False) # don't bother with HTTPS validation, it may not be configured yet
	except requests.exceptions.ConnectTimeout as e:
		raise IsBlocked()
	except requests.exceptions.ConnectionError as e:
		if "Connection refused" in str(e):
			raise IsBlocked()
		raise # some other unexpected condition

	# return response status code
	if r.status_code != expected_status:
		r.raise_for_status() # anything but 200
		raise IOError("Got unexpected status code %s." % r.status_code)

# define how to run a test

def restart_fail2ban_service(final=False):
	# Log in over SSH to restart fail2ban.
	command = "sudo fail2ban-client reload"
	if not final:
		# Stop recidive jails during testing.
		command += " && sudo fail2ban-client stop recidive"
	os.system("%s \"%s\"" % (ssh_command, command))

def testfunc_runner(i, testfunc, *args):
	print(i+1, end=" ", flush=True)
	testfunc(*args)

def run_test(testfunc, args, count, within_seconds, parallel):
	# Run testfunc count times in within_seconds seconds (and actually
	# within a little less time so we're sure we're under the limit).
	#
	# Because some services are slow, like IMAP, we can't necessarily
	# run testfunc sequentially and still get to count requests within
	# the required time. So we split the requests across threads.

	import requests.exceptions
	from multiprocessing import Pool

	restart_fail2ban_service()

	# Log.
	print(testfunc.__name__, " ".join(str(a) for a in args), "...")

	# Record the start time so we can know how to evenly space our
	# calls to testfunc.
	start_time = time.time()

	with Pool(parallel) as p:
		# Distribute the requests across the pool.
		asyncresults = []
		for i in range(count):
			ar = p.apply_async(testfunc_runner, [i, testfunc] + list(args))
			asyncresults.append(ar)

		# Wait for all runs to finish.
		p.close()
		p.join()

		# Check for errors.
		for ar in asyncresults:
			try:
				ar.get()
			except IsBlocked:
				print("Test machine prematurely blocked!")
				return False

	# Did we make enough requests within the limit?
	if (time.time()-start_time) > within_seconds:
		raise Exception("Test failed to make %s requests in %d seconds." % (count, within_seconds))

	# Wait a moment for the block to be put into place.
	time.sleep(4)

	# The next call should fail.
	print("*", end=" ", flush=True)
	try:
		testfunc(*args)
	except IsBlocked:
		# Success -- this one is supposed to be refused.
		print("blocked [OK]")
		return True # OK

	print("not blocked!")
	return False

######################################################################

if __name__ == "__main__":
	# run tests

	# SMTP bans at 10 even though we say 20 in the config because we get
	# doubled-up warnings in the logs, we'll let that be for now
	run_test(smtp_test, [], 10, 30, 8)

	# IMAP
	run_test(imap_test, [], 20, 30, 4)

	# Mail-in-a-Box control panel
	run_test(http_test, ["/admin/me", 200], 20, 30, 1)

	# Munin via the Mail-in-a-Box control panel
	run_test(http_test, ["/admin/munin/", 401], 20, 30, 1)

	# ownCloud
	run_test(http_test, ["/cloud/remote.php/webdav", 401, None, None, ["aa", "aa"]], 20, 120, 1)

	# restart fail2ban so that this client machine is no longer blocked
	restart_fail2ban_service(final=True)
