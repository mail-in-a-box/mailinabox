#!/usr/bin/python3

import sys, getpass, urllib.request, urllib.error, json

def mgmt(cmd, data=None, is_json=False):
	# The base URL for the management daemon. (Listens on IPv4 only.)
	mgmt_uri = 'http://127.0.0.1:10222'

	setup_key_auth(mgmt_uri)

	req = urllib.request.Request(mgmt_uri + cmd, urllib.parse.urlencode(data).encode("utf8") if data else None)
	try:
		response = urllib.request.urlopen(req)
	except urllib.error.HTTPError as e:
		if e.code == 401:
			try:
				print(e.read().decode("utf8"))
			except:
				pass
			print("The management daemon refused access. The API key file may be out of sync. Try 'service mailinabox restart'.", file=sys.stderr)
		elif hasattr(e, 'read'):
			print(e.read().decode('utf8'), file=sys.stderr)
		else:
			print(e, file=sys.stderr)
		sys.exit(1)
	resp = response.read().decode('utf8')
	if is_json: resp = json.loads(resp)
	return resp

def read_password():
	first  = getpass.getpass('password: ')
	second = getpass.getpass(' (again): ')
	while first != second:
		print('Passwords not the same. Try again.')
		first  = getpass.getpass('password: ')
		second = getpass.getpass(' (again): ')
	return first

def setup_key_auth(mgmt_uri):
	key = open('/var/lib/mailinabox/api.key').read().strip()

	auth_handler = urllib.request.HTTPBasicAuthHandler()
	auth_handler.add_password(
		realm='Mail-in-a-Box Management Server',
		uri=mgmt_uri,
		user=key,
		passwd='')
	opener = urllib.request.build_opener(auth_handler)
	urllib.request.install_opener(opener)

if len(sys.argv) < 2:
	print("Usage: ")
	print("  tools/mail.py user  (lists users)")
	print("  tools/mail.py user add user@domain.com [password]")
	print("  tools/mail.py user password user@domain.com [password]")
	print("  tools/mail.py user remove user@domain.com")
	print("  tools/mail.py user make-admin user@domain.com")
	print("  tools/mail.py user remove-admin user@domain.com")
	print("  tools/mail.py user admins (lists admins)")
	print("  tools/mail.py alias  (lists aliases)")
	print("  tools/mail.py alias add incoming.name@domain.com sent.to@other.domain.com")
	print("  tools/mail.py alias add incoming.name@domain.com 'sent.to@other.domain.com, multiple.people@other.domain.com'")
	print("  tools/mail.py alias remove incoming.name@domain.com")
	print()
	print("Removing a mail user does not delete their mail folders on disk. It only prevents IMAP/SMTP login.")
	print()

elif sys.argv[1] == "user" and len(sys.argv) == 2:
	# Dump a list of users, one per line. Mark admins with an asterisk.
	users = mgmt("/mail/users?format=json", is_json=True)
	for user in users:
		if user['status'] == 'inactive': continue
		print(user['email'], end='')
		if "admin" in user['privileges']:
			print("*", end='')
		print()

elif sys.argv[1] == "user" and sys.argv[2] in ("add", "password"):
	if len(sys.argv) < 5:
		if len(sys.argv) < 4:
			email = input("email: ")
		else:
			email = sys.argv[3]
		pw = read_password()
	else:
		email, pw = sys.argv[3:5]

	if sys.argv[2] == "add":
		print(mgmt("/mail/users/add", { "email": email, "password": pw }))
	elif sys.argv[2] == "password":
		print(mgmt("/mail/users/password", { "email": email, "password": pw }))

elif sys.argv[1] == "user" and sys.argv[2] == "remove" and len(sys.argv) == 4:
	print(mgmt("/mail/users/remove", { "email": sys.argv[3] }))

elif sys.argv[1] == "user" and sys.argv[2] in ("make-admin", "remove-admin") and len(sys.argv) == 4:
	if sys.argv[2] == "make-admin":
		action = "add"
	else:
		action = "remove"
	print(mgmt("/mail/users/privileges/" + action, { "email": sys.argv[3], "privilege": "admin" }))

elif sys.argv[1] == "user" and sys.argv[2] == "admins":
	# Dump a list of admin users.
	users = mgmt("/mail/users?format=json", is_json=True)
	for user in users:
		if "admin" in user['privileges']:
			print(user['email'])

elif sys.argv[1] == "alias" and len(sys.argv) == 2:
	print(mgmt("/mail/aliases"))

elif sys.argv[1] == "alias" and sys.argv[2] == "add" and len(sys.argv) == 5:
	print(mgmt("/mail/aliases/add", { "source": sys.argv[3], "destination": sys.argv[4] }))

elif sys.argv[1] == "alias" and sys.argv[2] == "remove" and len(sys.argv) == 4:
	print(mgmt("/mail/aliases/remove", { "source": sys.argv[3] }))

else:
	print("Invalid command-line arguments.")
	sys.exit(1)

