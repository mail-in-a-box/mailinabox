#!/usr/bin/env python3
# -*- indent-tabs-mode: t; tab-width: 4; -*-
#
# Tests sending and receiving mail by sending a test message to yourself.

import sys, imaplib, smtplib, uuid, time
import socket, dns.reversename, dns.resolver


def usage():
	print("Usage: test_mail.py [options] hostname login password")
	print("Send, then delete message")
	print("  options")
	print("    -smtpd: connect to port 25 and ignore login and password")
	print("    -f <email>: use <email> as the MAIL FROM address")
	print("    -to <email> <pass>: recipient of email and password")
	print("    -hfrom <email>: header From: email")
	print("    -subj <subject>: subject of the message (required with --no-send)")
	print("    -no-send: don't send, just delete")
	print("    -no-delete: don't delete, just send")
	print("    -timeout <seconds>: how long to wait for message")
	print("");
	sys.exit(1)

def if_unset(a,b):
	return b if a is None else a

# option defaults
smtpd=False      # deliver mail to port 25, not submission (ignore login/pw)
host=None        # smtp server address
login=None       # smtp server login
pw=None          # smtp server password
emailfrom=None   # MAIL FROM address
headerfrom=None  # Header From: address
emailto=None     # RCPT TO address
emailto_pw=None  # recipient password for imap login
send_msg=True    # deliver message
delete_msg=True  # login to imap and delete message
wait_timeout=30  # abandon timeout wiating for message delivery
wait_cycle_sleep=5  # delay between delivery checks
subject="Mail-in-a-Box Automated Test Message " + uuid.uuid4().hex  # message subject

# process command line
argi=1
while argi<len(sys.argv):
	arg=sys.argv[argi]
	arg_remaining = len(sys.argv) - argi - 1
	if not arg.startswith('-'):
		break
	if arg=="-smptd":
		smtpd=True
		argi+=1
	elif (arg=="-f" or arg=="-from") and arg_remaining>0:
		emailfrom=sys.argv[argi+1]
		argi+=2
	elif arg=="-hfrom" and arg_remaining>0:
		headerfrom=sys.argv[argi+1]
		argi+=2
	elif arg=="-to" and arg_remaining>1:
		emailto=sys.argv[argi+1]
		emailto_pw=sys.argv[argi+2]
		argi+=3
	elif arg=="-subj" and arg_remaining>1:
		subject=sys.argv[argi+1]
		argi+=2
	elif arg=="-no-send":
		send_msg=False
		argi+=1
	elif arg=="-no-delete":
		delete_msg=False
		argi+=1
	elif arg=="-timeout" and arg_remaining>1:
		wait_timeout=int(sys.argv[argi+1])
		argi+=2
	else:
		usage()
		
if not smtpd:
	if len(sys.argv) - argi != 3: usage()
	host, login, pw = sys.argv[argi:argi+3]
	argi+=3
	port=465
else:
	if len(sys.argv) - argi != 1: usage()
	host = sys.argv[argi]
	argi+=1
	port=25

emailfrom = if_unset(emailfrom, login)
headerfrom = if_unset(headerfrom, emailfrom)
emailto = if_unset(emailto, login)
emailto_pw = if_unset(emailto_pw, pw)

msg = """From: {headerfrom}
To: {emailto}
Subject: {subject}

This is a test message. It should be automatically deleted by the test script.""".format(
	headerfrom=headerfrom,
	emailto=emailto,
	subject=subject,
	)

def imap_login(host, login, pw):
	# Attempt to login with IMAP. Our setup uses email addresses
	# as IMAP/SMTP usernames.
	try:
		M = imaplib.IMAP4_SSL(host)
		M.login(login, pw)
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
	return M


def imap_search_for(M, subject):
	# Read the subject lines of all of the emails in the inbox
	# to find our test message, then return the number
	typ, data = M.search(None, 'ALL')
	for num in data[0].split():
		typ, data = M.fetch(num, '(BODY[HEADER.FIELDS (SUBJECT)])')
		imapsubjectline = data[0][1].strip().decode("utf8")
		if imapsubjectline == "Subject: " + subject:
			return num
	return None


def imap_test_dkim(M, num):
	# To test DKIM, download the whole mssage body. Unfortunately,
	# pydkim doesn't actually work.
	# You must 'sudo apt-get install python3-dkim python3-dnspython' first.
	#typ, msgdata = M.fetch(num, '(RFC822)')
	#msg = msgdata[0][1]
	#if dkim.verify(msg):
	#	print("DKIM signature on the test message is OK (verified).")
	#else:
	#	print("DKIM signature on the test message failed verification.")
	pass


def smtp_login(host, login, pw, port):
	# Connect to the server on the SMTP submission TLS port.
	if port == 587 or port == 25:
		server = smtplib.SMTP(host, port)
		server.starttls()
	else:
		server = smtplib.SMTP_SSL(host)
	#server.set_debuglevel(1)

	# Verify that the EHLO name matches the server's reverse DNS.
	ipaddr = socket.gethostbyname(host) # IPv4 only!
	reverse_ip = dns.reversename.from_address(ipaddr) # e.g. "1.0.0.127.in-addr.arpa."
	try:
		reverse_dns = dns.resolver.resolve(reverse_ip, 'PTR')[0].target.to_text(omit_final_dot=True) # => hostname
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
	if login is not None and login != "":
		server.login(login, pw)
	return server




if send_msg:
	# Attempt to send a mail.
	server = smtp_login(host, login, pw, port)
	server.sendmail(emailfrom, [emailto], msg)
	server.quit()
	print("SMTP submission is OK.")


if delete_msg:
	# Wait for mail and delete it.
	M = imap_login(host, emailto, emailto_pw)

	start_time = time.time()
	found = False
	if send_msg:
		# Wait so the message can propagate to the inbox.
		time.sleep(wait_cycle_sleep / 2)

	while not found and time.time() - start_time < wait_timeout:
		for mailbox in ['INBOX', 'Spam']:
			M.select(mailbox)
			num = imap_search_for(M, subject)
			if num is not None:
				# Delete the test message.
				found = True
				imap_test_dkim(M, num)
				M.store(num, '+FLAGS', '\\Deleted')
				M.expunge()
				print("Message %s deleted successfully from %s." % (num, mailbox))
				break

		if not found:
			print("Test message not present in the inbox yet...")
			time.sleep(wait_cycle_sleep)
		
	M.close()
	M.logout()
	
	if not found:
		raise TimeoutError("Timeout waiting for message")

if send_msg and delete_msg:
	print("Test message sent & received successfully.")

