#!/usr/local/lib/mailinabox/env/bin/python

# Reads in STDIN. If the stream is not empty, mail it to the system administrator.

import sys, traceback

import html
import smtplib

from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

# In Python 3.6:
#from email.message import Message

from utils import load_environment

# Load system environment info.
env = load_environment()

# Process command line args.
subject = sys.argv[1]

# Administrator's email address.
admin_addr = "administrator@" + env['PRIMARY_HOSTNAME']

# Read in STDIN.
try:
        content = sys.stdin.read().strip()
except:
        print("error occured while cleaning input text")
        traceback.print_exc()
        sys.exit(1)

# If there's nothing coming in, just exit.
if content == "":
	sys.exit(0)

# create MIME message
msg = MIMEMultipart('alternative')

# In Python 3.6:
#msg = Message()

msg['From'] = "\"%s\" <%s>" % (env['PRIMARY_HOSTNAME'], admin_addr)
msg['To'] = admin_addr
msg['Subject'] = "[%s] %s" % (env['PRIMARY_HOSTNAME'], subject)

content_html = "<html><body><pre>{}</pre></body></html>".format(html.escape(content))

msg.attach(MIMEText(content, 'plain'))
msg.attach(MIMEText(content_html, 'html'))

# In Python 3.6:
#msg.set_content(content)
#msg.add_alternative(content_html, "html")

# send
smtpclient = smtplib.SMTP('127.0.0.1', 25)
smtpclient.ehlo()
smtpclient.sendmail(
        admin_addr, # MAIL FROM
        admin_addr, # RCPT TO
        msg.as_string())
smtpclient.quit()
