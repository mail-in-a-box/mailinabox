#!/usr/bin/env python3
# Tests sending and receiving mail by sending a test message to yourself.

import sys, imaplib, smtplib, uuid, time
import socket, dns.reversename, dns.resolver

if len(sys.argv) < 3:
	print("Usage: tests/mail.py hostname emailaddress password")
	sys.exit(1)

host, emailaddress, pw = sys.argv[1:4]

# Attempt to login with IMAP. Our setup uses email addresses
# as IMAP/SMTP usernames.
try:
	M = imaplib.IMAP4_SSL(host)
	M.login(emailaddress, pw)
except OSError as e:
	print("Connection error:", e)
	sys.exit(1)
except imaplib.IMAP4.error as e:
	# any sort of login error
	e = ", ".join(a.decode("utf8") for a in e.args)
	print("IMAP error:", e)
	sys.exit(1)

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

# Connect to the server on the SMTP submission TLS port.
server = smtplib.SMTP_SSL(host)
#server.set_debuglevel(1)

# Verify that the EHLO name matches the server's reverse DNS.
ipaddr = socket.gethostbyname(host) # IPv4 only!
reverse_ip = dns.reversename.from_address(ipaddr) # e.g. "1.0.0.127.in-addr.arpa."
try:
	reverse_dns = dns.resolver.query(reverse_ip, 'PTR')[0].target.to_text(omit_final_dot=True) # => hostname
except dns.resolver.NXDOMAIN:
	print("Reverse DNS lookup failed for %s. SMTP EHLO name check skipped." % ipaddr)
	reverse_dns = None
if reverse_dns is not None:
	server.ehlo_or_helo_if_needed() # must send EHLO before getting the server's EHLO name
	helo_name = server.ehlo_resp.decode("utf8").split("\n")[0] # first line is the EHLO name
	if helo_name != reverse_dns:
		print("The server's EHLO name does not match its reverse hostname. Check DNS settings.")
	else:
		print("SMTP EHLO name (%s) is OK." % helo_name)

# Login and send a test email.
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
