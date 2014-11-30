#!/usr/bin/python3
#
# This script implement's Dovecot's checkpassword authentication mechanism:
# http://wiki2.dovecot.org/AuthDatabase/CheckPassword?action=show&redirect=PasswordDatabase%2FCheckPassword
#
# This allows us to perform our own password validation.
#
# We will issue an HTTP request to our management server to perform
# authentication. This gives us the opportunity to implement things
# like one time passwords and app-specific passwords.

import sys, os, urllib.request, base64, json, traceback

try:
	# Read fd 3 which provides the username and password separated
	# by NULLs and two other undocumented/empty fields.
	creds = b''
	while True:
		b = os.read(3, 1024)
		if len(b) == 0: break
		creds += b
	email, pw, dummy, dummy = creds.split(b'\x00')

	# Call the management server's "/me" method with the
	# provided credentials
	req = urllib.request.Request('http://127.0.0.1:10222/me')
	req.add_header(b'Authorization', b'Basic ' + base64.b64encode(email + b':' + pw))
	response = urllib.request.urlopen(req)

	# The response is always success and always a JSON object
	# indicating the authentication result.
	resp = response.read().decode('utf8')
	resp = json.loads(resp)
	if not isinstance(resp, dict): raise ValueError("Response is not a JSON object.")

except:
	# Handle all exceptions. Print what happens (ends up in syslog, thanks
	# to dovecot) and return an exit status that indicates temporary failure.
	traceback.print_exc()
	print(json.dumps(dict(os.environ), indent=2), file=sys.stderr)
	sys.exit(111)

if resp.get('status') != 'authorized':
	# Indicates login failure.
	# (sys.exit should not be inside try/except.)
	sys.exit(1)

# Signal ok by executing the indicated process. (Note that
# the second parameter is the 0th argument to the called
# process, which is required and is typically the file
# itself.)
os.execl(sys.argv[1], sys.argv[1])

