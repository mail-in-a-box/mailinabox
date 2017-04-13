#!/usr/bin/python3

# Reads in STDIN. If the stream is not empty, mail it to the system administrator.

import sys
import time

import smtplib
from email.message import Message

from utils import load_environment

# Load system environment info.
env = load_environment()

# Process command line args.
subject = sys.argv[1]

# Administrator's email address.
admin_addr = "administrator@" + env['PRIMARY_HOSTNAME']

# Read in STDIN.
content = sys.stdin.read().strip()

# Checks if content is nil. If nil, it tries again, with 5 second wait time. after 10 attempts, quits
i = 0
while content == "":
	content = sys.stdin.read().strip()
	time.sleep(5)
	i = i + 1
	if i == 10:
		sys.exit(0)
	

# create MIME message
msg = Message()
msg['From'] = "\"%s\" <%s>" % (env['PRIMARY_HOSTNAME'], admin_addr)
msg['To'] = admin_addr
msg['Subject'] = "[%s] %s" % (env['PRIMARY_HOSTNAME'], subject)
msg.set_payload(content, "UTF-8")

# send
smtpclient = smtplib.SMTP('127.0.0.1', 25)
smtpclient.ehlo()
smtpclient.sendmail(
        admin_addr, # MAIL FROM
        admin_addr, # RCPT TO
        msg.as_string())
smtpclient.quit()
