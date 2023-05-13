#!/usr/local/lib/mailinabox/env/bin/python
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####


# Reads in STDIN. If the stream is not empty, mail it to the system administrator.

import sys

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
content = sys.stdin.read().strip()

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

content_html = '<html><body><pre style="overflow-x: scroll; white-space: pre;">{}</pre></body></html>'.format(html.escape(content))

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
