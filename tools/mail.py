#!/usr/bin/python3

import sys, urllib.request, urllib.error

def mgmt(cmd, data=None):
	req = urllib.request.Request('http://localhost:10222' + cmd, urllib.parse.urlencode(data).encode("utf8") if data else None)
	try:
		response = urllib.request.urlopen(req)
	except urllib.error.HTTPError as e:
		print(e.read().decode('utf8'))
		sys.exit(1)
	return response.read().decode('utf8')

if len(sys.argv) < 2:
	print("Usage: ")
	print("  tools/mail.py user  (lists users)")
	print("  tools/mail.py user add user@domain.com [password]")
	print("  tools/mail.py user password user@domain.com [password]")
	print("  tools/mail.py user remove user@domain.com")
	print("  tools/mail.py alias  (lists aliases)")
	print("  tools/mail.py alias add incoming.name@domain.com sent.to@other.domain.com")
	print("  tools/mail.py alias remove incoming.name@domain.com")
	print()
	print("Removing a mail user does not delete their mail folders on disk. It only prevents IMAP/SMTP login.")
	print()

elif sys.argv[1] == "user" and len(sys.argv) == 2:
	print(mgmt("/mail/users"))

elif sys.argv[1] == "user" and sys.argv[2] in ("add", "password"):
	if len(sys.argv) < 5:
		if len(sys.argv) < 4:
			email = input("email: ")
		else:
			email = sys.argv[3]
		pw = input("password: ")
	else:
		email, pw = sys.argv[3:5]

	if sys.argv[2] == "add":
		print(mgmt("/mail/users/add", { "email": email, "password": pw }))
	elif sys.argv[2] == "password":
		print(mgmt("/mail/users/password", { "email": email, "password": pw }))

elif sys.argv[1] == "user" and sys.argv[2] == "remove" and len(sys.argv) == 4:
	print(mgmt("/mail/users/remove", { "email": sys.argv[3] }))

elif sys.argv[1] == "alias" and len(sys.argv) == 2:
	print(mgmt("/mail/aliases"))

elif sys.argv[1] == "alias" and sys.argv[2] == "add" and len(sys.argv) == 5:
	print(mgmt("/mail/aliases/add", { "source": sys.argv[3], "destination": sys.argv[4] }))

elif sys.argv[1] == "alias" and sys.argv[2] == "remove" and len(sys.argv) == 4:
	print(mgmt("/mail/aliases/remove", { "source": sys.argv[3] }))

else:
	print("Invalid command-line arguments.")

