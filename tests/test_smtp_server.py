#!/usr/bin/env python3
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####

import smtplib, sys

if len(sys.argv) < 3:
        print("Usage: tests/smtp_server.py host email.to email.from")
        sys.exit(1)

host, toaddr, fromaddr = sys.argv[1:4]
msg = """From: %s
To: %s
Subject: SMTP server test

This is a test message.""" % (fromaddr, toaddr)

server = smtplib.SMTP(host, 25)
server.set_debuglevel(1)
server.sendmail(fromaddr, [toaddr], msg)
server.quit()

