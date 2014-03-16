#!/usr/bin/python3

import sys, sqlite3, subprocess, shutil, os

# Load STORAGE_ROOT setting from /etc/mailinabox.conf.
env = { }
for line in open("/etc/mailinabox.conf"): env.setdefault(*line.strip().split("=", 1))

# Connect to database.
conn = sqlite3.connect(env["STORAGE_ROOT"] + "/mail/users.sqlite")
c = conn.cursor()

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
	c.execute('SELECT email FROM users')
	for row in c.fetchall():
		print(row[0])

elif sys.argv[1] == "user" and sys.argv[2] in ("add", "password"):
	if len(sys.argv) < 5:
		if len(sys.argv) < 4:
			email = input("email: ")
		else:
			email = sys.argv[3]
		pw = input("password: ")
	else:
		email, pw = sys.argv[3:5]

	# hash the password
	pw = subprocess.check_output(["/usr/bin/doveadm", "pw", "-s", "SHA512-CRYPT", "-p", pw]).strip()

	if sys.argv[2] == "add":
		try:
			c.execute("INSERT INTO users (email, password) VALUES (?, ?)", (email, pw))
		except sqlite3.IntegrityError:
			print("User already exists.")
			sys.exit(1)
			
		conn.commit() # write it before next step
		
		# Create the user's INBOX and Spam folders and subscribe them.

		# Check if the mailboxes exist before creating them. When creating a user that had previously
		# been deleted, the mailboxes will still exist because they are still on disk.
		existing_mboxes = subprocess.check_output(["doveadm", "mailbox", "list", "-u", email, "-8"]).decode("utf8").split("\n")
		
		if "INBOX" not in existing_mboxes: subprocess.check_call(["doveadm", "mailbox", "create", "-u", email, "-s", "INBOX"])
		if "Spam" not in existing_mboxes: subprocess.check_call(["doveadm", "mailbox", "create", "-u", email, "-s", "Spam"])
		
		# Create the user's sieve script to move spam into the Spam folder, and make it owned by mail.
		maildirstat = os.stat(env["STORAGE_ROOT"] + "/mail/mailboxes")
		(em_user, em_domain) = email.split("@", 1)
		user_mail_dir = env["STORAGE_ROOT"] + ("/mail/mailboxes/%s/%s" % (em_domain, em_user))
		if not os.path.exists(user_mail_dir):
			os.makedirs(user_mail_dir)
			os.chown(user_mail_dir, maildirstat.st_uid, maildirstat.st_gid)
		shutil.copyfile("conf/dovecot_sieve.txt", user_mail_dir + "/.dovecot.sieve")
		os.chown(user_mail_dir + "/.dovecot.sieve", maildirstat.st_uid, maildirstat.st_gid)
		
	elif sys.argv[2] == "password":
		c.execute("UPDATE users SET password=? WHERE email=?", (pw, email))
		if c.rowcount != 1:
			print("That's not a user.")
			sys.exit(1)

elif sys.argv[1] == "user" and sys.argv[2] == "remove" and len(sys.argv) == 4:
	c.execute("DELETE FROM users WHERE email=?", (sys.argv[3],))
	if c.rowcount != 1:
		print("That's not a user.")
		sys.exit(1)

elif sys.argv[1] == "alias" and len(sys.argv) == 2:
	c.execute('SELECT source, destination FROM aliases')
	for row in c.fetchall():
		print(row[0], "=>", row[1])

elif sys.argv[1] == "alias" and sys.argv[2] == "add" and len(sys.argv) == 5:
	try:
		c.execute("INSERT INTO aliases (source, destination) VALUES (?, ?)", (sys.argv[3], sys.argv[4]))
	except sqlite3.IntegrityError:
		print("Alias already exists.")
		sys.exit(1)

elif sys.argv[1] == "alias" and sys.argv[2] == "remove" and len(sys.argv) == 4:
	c.execute("DELETE FROM aliases WHERE source=?", (sys.argv[3],))
	if c.rowcount != 1:
		print("That's not an alias.")
		sys.exit(1)

else:
	print("Invalid command-line arguments.")

conn.commit()
