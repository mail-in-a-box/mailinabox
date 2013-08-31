#!/usr/bin/python3
import smtplib, sys

if len(sys.argv) < 3:
        print("Usage: tests/smtp_submission.py host email.from pw  email.to")
        sys.exit(1)

host, fromaddr, pw, toaddr = sys.argv[1:5]
msg = """From: %s
To: %s
Subject: SMTP server test

This is a test message.""" % (fromaddr, toaddr)

server = smtplib.SMTP(host, 587)
server.set_debuglevel(1)
server.starttls()
server.login(fromaddr, pw)
server.sendmail(fromaddr, [toaddr], msg)
server.quit()


