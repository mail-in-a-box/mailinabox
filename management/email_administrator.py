#!/usr/bin/python3

# Reads in STDIN. If the stream is not empty, mail it to the system administrator.

import sys

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

# If there's nothing coming in, just exit.
while content == "":
	content = sys.stdin.read().strip()

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
