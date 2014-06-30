#!/usr/bin/python3

import subprocess, shutil, os, sqlite3, re
import utils

def validate_email(email, strict):
	# There are a lot of characters permitted in email addresses, but
	# Dovecot's sqlite driver seems to get confused if there are any
	# unusual characters in the address. Bah. Also note that since
	# the mailbox path name is based on the email address, the address
	# shouldn't be absurdly long and must not have a forward slash.

	if len(email) > 255: return False

	if strict:
		# For Dovecot's benefit, only allow basic characters.
		ATEXT = r'[\w\-]'
	else:
		# Based on RFC 2822 and https://github.com/SyrusAkbary/validate_email/blob/master/validate_email.py,
		# these characters are permitted in email address.
		ATEXT = r'[\w!#$%&\'\*\+\-/=\?\^`\{\|\}~]' # see 3.2.4

	DOT_ATOM_TEXT = ATEXT + r'+(?:\.' + ATEXT + r'+)*'      # see 3.2.4
	DOT_ATOM_TEXT2 = ATEXT + r'+(?:\.' + ATEXT + r'+)+'      # as above, but with a "+" since the host part must be under some TLD
	ADDR_SPEC = '^%s@%s$' % (DOT_ATOM_TEXT, DOT_ATOM_TEXT2) # see 3.4.1

	return re.match(ADDR_SPEC, email)

def open_database(env, with_connection=False):
	conn = sqlite3.connect(env["STORAGE_ROOT"] + "/mail/users.sqlite")
	if not with_connection:
		return conn.cursor()
	else:
		return conn, conn.cursor()

def get_mail_users(env):
	c = open_database(env)
	c.execute('SELECT email FROM users')
	return [row[0] for row in c.fetchall()]

def get_mail_aliases(env):
	c = open_database(env)
	c.execute('SELECT source, destination FROM aliases')
	return [(row[0], row[1]) for row in c.fetchall()]

def get_mail_domains(env):
	def get_domain(emailaddr):
		return emailaddr.split('@', 1)[1]
	return set([get_domain(addr) for addr in get_mail_users(env)] + [get_domain(addr1) for addr1, addr2 in get_mail_aliases(env)])

def add_mail_user(email, pw, env):
	if not validate_email(email, True):
		return ("Invalid email address.", 400)

	# get the database
	conn, c = open_database(env, with_connection=True)

	# hash the password
	pw = utils.shell('check_output', ["/usr/bin/doveadm", "pw", "-s", "SHA512-CRYPT", "-p", pw]).strip()

	# add the user to the database
	try:
		c.execute("INSERT INTO users (email, password) VALUES (?, ?)", (email, pw))
	except sqlite3.IntegrityError:
		return ("User already exists.", 400)
		
	# write databasebefore next step
	conn.commit()

	# Create the user's INBOX and Spam folders and subscribe them.

	# Check if the mailboxes exist before creating them. When creating a user that had previously
	# been deleted, the mailboxes will still exist because they are still on disk.
	try:
		existing_mboxes = utils.shell('check_output', ["doveadm", "mailbox", "list", "-u", email, "-8"], capture_stderr=True).split("\n")
	except subprocess.CalledProcessError as e:
		c.execute("DELETE FROM users WHERE email=?", (email,))
		conn.commit()
		return ("Failed to initialize the user: " + e.output.decode("utf8"), 400)

	if "INBOX" not in existing_mboxes: utils.shell('check_call', ["doveadm", "mailbox", "create", "-u", email, "-s", "INBOX"])
	if "Spam" not in existing_mboxes: utils.shell('check_call', ["doveadm", "mailbox", "create", "-u", email, "-s", "Spam"])

	# Create the user's sieve script to move spam into the Spam folder, and make it owned by mail.
	maildirstat = os.stat(env["STORAGE_ROOT"] + "/mail/mailboxes")
	(em_user, em_domain) = email.split("@", 1)
	user_mail_dir = env["STORAGE_ROOT"] + ("/mail/mailboxes/%s/%s" % (em_domain, em_user))
	if not os.path.exists(user_mail_dir):
		os.makedirs(user_mail_dir)
		os.chown(user_mail_dir, maildirstat.st_uid, maildirstat.st_gid)
	shutil.copyfile(env["CONF_DIR"] + "/dovecot_sieve.txt", user_mail_dir + "/.dovecot.sieve")
	os.chown(user_mail_dir + "/.dovecot.sieve", maildirstat.st_uid, maildirstat.st_gid)

	# Update DNS in case any new domains are added.
	from dns_update import do_dns_update
	return do_dns_update(env)

def set_mail_password(email, pw, env):
	# hash the password
	pw = utils.shell('check_output', ["/usr/bin/doveadm", "pw", "-s", "SHA512-CRYPT", "-p", pw]).strip()

	# update the database
	conn, c = open_database(env, with_connection=True)
	c.execute("UPDATE users SET password=? WHERE email=?", (pw, email))
	if c.rowcount != 1:
		return ("That's not a user (%s)." % email, 400)
	conn.commit()
	return "OK"

def remove_mail_user(email, env):
	conn, c = open_database(env, with_connection=True)
	c.execute("DELETE FROM users WHERE email=?", (email,))
	if c.rowcount != 1:
		return ("That's not a user (%s)." % email, 400)
	conn.commit()

	# Update DNS in case any domains are removed.
	from dns_update import do_dns_update
	return do_dns_update(env)

def add_mail_alias(source, destination, env):
	if not validate_email(source, False):
		return ("Invalid email address.", 400)

	conn, c = open_database(env, with_connection=True)
	try:
		c.execute("INSERT INTO aliases (source, destination) VALUES (?, ?)", (source, destination))
	except sqlite3.IntegrityError:
		return ("Alias already exists (%s)." % source, 400)
	conn.commit()

	# Update DNS in case any new domains are added.
	from dns_update import do_dns_update
	return do_dns_update(env)

def remove_mail_alias(source, env):
	conn, c = open_database(env, with_connection=True)
	c.execute("DELETE FROM aliases WHERE source=?", (source,))
	if c.rowcount != 1:
		return ("That's not an alias (%s)." % source, 400)
	conn.commit()

	# Update DNS in case any domains are removed.
	from dns_update import do_dns_update
	return do_dns_update(env)

if __name__ == "__main__":
	import sys
	if len(sys.argv) > 2 and sys.argv[1] == "validate-email":
		# Validate that we can create a Dovecot account for a given string.
		if validate_email(sys.argv[2], True):
			sys.exit(0)
		else:
			sys.exit(1)
