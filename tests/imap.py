#!/usr/bin/python3
import imaplib, sys

if len(sys.argv) < 3:
	print("Usage: tests/imap.py host username password")
	sys.exit(1)

host, username, pw = sys.argv[1:4]

M = imaplib.IMAP4_SSL(host)
M.login(username, pw)
print("Login successful.")
M.select()
typ, data = M.search(None, 'ALL')
for num in data[0].split():
    typ, data = M.fetch(num, '(RFC822)')
    print('Message %s\n%s\n' % (num, data[0][1]))
M.close()
M.logout()

