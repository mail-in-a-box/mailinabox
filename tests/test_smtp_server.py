#!/usr/bin/env python3
import smtplib
import sys

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
