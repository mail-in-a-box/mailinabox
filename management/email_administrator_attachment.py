#!/usr/local/lib/mailinabox/env/bin/python

# Reads in STDIN. If the stream is not empty, mail it to the system administrator.

import sys

import html
import smtplib
import email

from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.base import MIMEBase
from email import encoders

# In Python 3.6:
#from email.message import Message

from utils import load_environment

# Load system environment info.
env = load_environment()

# Process command line args.
subject = sys.argv[1] or 'MIAB Administration'
body = sys.argv[2] or 'Please see the attachment. --Mail-in-a-Box'
attachmentname = sys.argv[3] or 'attachment.html'

# Administrator's email address.
admin_addr = "administrator@" + env['PRIMARY_HOSTNAME']

# Read in STDIN.
attachment = sys.stdin.read().strip()

# If there's nothing coming in, just exit.
if attachment == "":
    sys.exit(0)

# create MIME message
msg = MIMEMultipart('alternative')

# In Python 3.6:
#msg = Message()

msg['From'] = '"{}" <{}>'.format(env['PRIMARY_HOSTNAME'], admin_addr)
msg['To'] = admin_addr
msg['Subject'] = "[{}] {}".format(env['PRIMARY_HOSTNAME'], subject)

body_html = f'<html><body><pre style="overflow-x: scroll; white-space: pre;">{html.escape(body)}</pre></body></html>'

msg.attach(MIMEText(body, 'plain'))
msg.attach(MIMEText(body_html, 'html'))

# Attach content as file
part = MIMEBase('application', 'octet-stream')
part.set_payload(attachment);
encoders.encode_base64(part);
part.add_header('Content-Disposition', f"attachment; filename={attachmentname}")

msg.attach(part);
           
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
