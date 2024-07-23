#!/usr/bin/env python3
import smtplib, sys

if len(sys.argv) < 3:
        print("Usage: tests/smtp_server.py host email.to email.from")
        sys.exit(1)

host, toaddr, fromaddr = sys.argv[1:4]
msg = f"""From: {fromaddr}
To: {toaddr}
Subject: SMTP server test

This is a test message."""

server = smtplib.SMTP(host, 25)
server.set_debuglevel(1)
server.sendmail(fromaddr, [toaddr], msg)
server.quit()

