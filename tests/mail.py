#!/usr/bin/python3
# Tests sending and receiving mail by sending a test message to yourself.

import sys, imaplib, smtplib, uuid, time, dkim

if len(sys.argv) < 3:
	print("Usage: tests/mail.py hostname emailaddress password")
	sys.exit(1)

host, emailaddress, pw = sys.argv[1:4]

# Attempt to login with IMAP. Our setup uses email addresses
# as IMAP/SMTP usernames.
M = imaplib.IMAP4_SSL(host)
M.login(emailaddress, pw)
M.select()
print("IMAP login is OK.")

# Attempt to send a mail to ourself.
mailsubject = "Mail-in-a-Box Automated Test Message " + uuid.uuid4().hex
emailto = emailaddress
msg = """From: {emailaddress}
To: {emailto}
Subject: {subject}

This is a test message. It should be automatically deleted by the test script.""".format(
	emailaddress=emailaddress,
	emailto=emailto,
	subject=mailsubject,
	)
server = smtplib.SMTP(host, 587)
#server.set_debuglevel(1)
server.starttls()
server.login(emailaddress, pw)
server.sendmail(emailaddress, [emailto], msg)
server.quit()
print("SMTP submission is OK.")

while True:
	# Wait so the message can propagate to the inbox.
	time.sleep(10)

	# Read the subject lines of all of the emails in the inbox
	# to find our test message, and then delete it.
	found = False
	typ, data = M.search(None, 'ALL')
	for num in data[0].split():
		typ, data = M.fetch(num, '(BODY[HEADER.FIELDS (SUBJECT)])')
		imapsubjectline = data[0][1].strip().decode("utf8")
		if imapsubjectline == "Subject: " + mailsubject:
			# We found our test message.
			found = True

			# To test DKIM, download the whole mssage body. Unfortunately,
			# pydkim doesn't actually work.
			# You must 'sudo apt-get install python3-dkim python3-dnspython' first.
			#typ, msgdata = M.fetch(num, '(RFC822)')
			#msg = msgdata[0][1]
			#if dkim.verify(msg):
			#	print("DKIM signature on the test message is OK (verified).")
			#else:
			#	print("DKIM signature on the test message failed verification.")

			# Delete the test message.
			M.store(num, '+FLAGS', '\\Deleted')
			M.expunge()

			break

	if found:
		break

	print("Test message not present in the inbox yet...")

M.close()
M.logout()

print("Test message sent & received successfully.")
