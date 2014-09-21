#!/usr/bin/python3

import subprocess, shutil, os, sqlite3, re
import utils

def validate_email(email, mode=None):
	# There are a lot of characters permitted in email addresses, but
	# Dovecot's sqlite driver seems to get confused if there are any
	# unusual characters in the address. Bah. Also note that since
	# the mailbox path name is based on the email address, the address
	# shouldn't be absurdly long and must not have a forward slash.

	if len(email) > 255: return False

	if mode == 'user':
		# For Dovecot's benefit, only allow basic characters.
		ATEXT = r'[\w\-]'
	elif mode == 'alias':
		# For aliases, we can allow any valid email address.
		# Based on RFC 2822 and https://github.com/SyrusAkbary/validate_email/blob/master/validate_email.py,
		# these characters are permitted in email addresses.
		ATEXT = r'[\w!#$%&\'\*\+\-/=\?\^`\{\|\}~]' # see 3.2.4
	else:
		raise ValueError(mode)

	# per RFC 2822 3.2.4
	DOT_ATOM_TEXT_LOCAL = ATEXT + r'+(?:\.' + ATEXT + r'+)*'
	if mode == 'alias':
		# For aliases, Postfix accepts '@domain.tld' format for
		# catch-all addresses. Make the local part optional.
		DOT_ATOM_TEXT_LOCAL = '(?:' + DOT_ATOM_TEXT_LOCAL + ')?'

	# as above, but we can require that the host part have at least
	# one period in it, so use a "+" rather than a "*" at the end
	DOT_ATOM_TEXT_HOST = ATEXT + r'+(?:\.' + ATEXT + r'+)+'

	# per RFC 2822 3.4.1
	ADDR_SPEC = '^%s@%s$' % (DOT_ATOM_TEXT_LOCAL, DOT_ATOM_TEXT_HOST)

	return re.match(ADDR_SPEC, email)

def open_database(env, with_connection=False):
	conn = sqlite3.connect(env["STORAGE_ROOT"] + "/mail/users.sqlite")
	if not with_connection:
		return conn.cursor()
	else:
		return conn, conn.cursor()

def get_mail_users(env, as_json=False):
	c = open_database(env)
	c.execute('SELECT email, privileges FROM users')

	# turn into a list of tuples, but sorted by domain & email address
	users = { row[0]: row[1] for row in c.fetchall() } # make dict
	users = [ (email, users[email]) for email in utils.sort_email_addresses(users.keys(), env) ]

	if not as_json:
		return [email for email, privileges in users]
	else:
		aliases = get_mail_alias_map(env)
		return [
			{
				"email": email,
				"privileges": parse_privs(privileges),
				"status": "active",
				"aliases": [
					(alias, sorted(evaluate_mail_alias_map(alias, aliases, env)))
					for alias in aliases.get(email.lower(), [])
					]
			}
			for email, privileges in users
			 ]

def get_archived_mail_users(env):
	real_users = set(get_mail_users(env))
	root = os.path.join(env['STORAGE_ROOT'], 'mail/mailboxes')
	ret = []
	for domain_enc in os.listdir(root):
		for user_enc in os.listdir(os.path.join(root, domain_enc)):
			email = utils.unsafe_domain_name(user_enc) + "@" + utils.unsafe_domain_name(domain_enc)
			if email in real_users: continue
			ret.append({
				"email": email, 
				"privileges": "",
				"status": "inactive"
			})
	return ret

def get_mail_aliases(env, as_json=False):
	c = open_database(env)
	c.execute('SELECT source, destination FROM aliases')
	aliases = { row[0]: row[1] for row in c.fetchall() } # make dict

	# put in a canonical order: sort by domain, then by email address lexicographically
	aliases = [ (source, aliases[source]) for source in utils.sort_email_addresses(aliases.keys(), env) ] # sort

	# but put automatic aliases to administrator@ last
	aliases.sort(key = lambda x : x[1] == get_system_administrator(env))

	if as_json:
		required_aliases = get_required_aliases(env)
		aliases = [
			{
				"source": alias[0],
				"destination": [d.strip() for d in alias[1].split(",")],
				"required": alias[0] in required_aliases or alias[0] == get_system_administrator(env),
			}
			for alias in aliases
		]
	return aliases

def get_mail_alias_map(env):
	aliases = { }
	for alias, targets in get_mail_aliases(env):
		for em in targets.split(","):
			em = em.strip().lower()
			aliases.setdefault(em, []).append(alias)
	return aliases

def evaluate_mail_alias_map(email, aliases,  env):
	ret = set()
	for alias in aliases.get(email.lower(), []):
		ret.add(alias)
		ret |= evaluate_mail_alias_map(alias, aliases, env)
	return ret

def get_mail_domains(env, filter_aliases=lambda alias : True):
	def get_domain(emailaddr):
		return emailaddr.split('@', 1)[1]
	return set(
		   [get_domain(addr) for addr in get_mail_users(env)]
		 + [get_domain(source) for source, target in get_mail_aliases(env) if filter_aliases((source, target)) ]
		 )

def add_mail_user(email, pw, privs, env):
	# validate email
	if email.strip() == "":
		return ("No email address provided.", 400)
	if not validate_email(email, mode='user'):
		return ("Invalid email address.", 400)

	validate_password(pw)

	# validate privileges
	if privs is None or privs.strip() == "":
		privs = []
	else:
		privs = privs.split("\n")
		for p in privs:
			validation = validate_privilege(p)
			if validation: return validation

	# get the database
	conn, c = open_database(env, with_connection=True)

	# hash the password
	pw = utils.shell('check_output', ["/usr/bin/doveadm", "pw", "-s", "SHA512-CRYPT", "-p", pw]).strip()

	# add the user to the database
	try:
		c.execute("INSERT INTO users (email, password, privileges) VALUES (?, ?, ?)",
			(email, pw, "\n".join(privs)))
	except sqlite3.IntegrityError:
		return ("User already exists.", 400)

	# write databasebefore next step
	conn.commit()

	# Create the user's INBOX, Spam, and Drafts folders, and subscribe them.
	# K-9 mail will poll every 90 seconds if a Drafts folder does not exist, so create it
	# to avoid unnecessary polling.

	# Check if the mailboxes exist before creating them. When creating a user that had previously
	# been deleted, the mailboxes will still exist because they are still on disk.
	try:
		existing_mboxes = utils.shell('check_output', ["doveadm", "mailbox", "list", "-u", email, "-8"], capture_stderr=True).split("\n")
	except subprocess.CalledProcessError as e:
		c.execute("DELETE FROM users WHERE email=?", (email,))
		conn.commit()
		return ("Failed to initialize the user: " + e.output.decode("utf8"), 400)

	for folder in ("INBOX", "Spam", "Drafts"):
		if folder not in existing_mboxes:
			utils.shell('check_call', ["doveadm", "mailbox", "create", "-u", email, "-s", folder])

	# Update things in case any new domains are added.
	return kick(env, "mail user added")

def set_mail_password(email, pw, env):
	validate_password(pw)
	
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

	# Update things in case any domains are removed.
	return kick(env, "mail user removed")

def parse_privs(value):
	return [p for p in value.split("\n") if p.strip() != ""]

def get_mail_user_privileges(email, env):
	c = open_database(env)
	c.execute('SELECT privileges FROM users WHERE email=?', (email,))
	rows = c.fetchall()
	if len(rows) != 1:
		return ("That's not a user (%s)." % email, 400)
	return parse_privs(rows[0][0])

def validate_privilege(priv):
	if "\n" in priv or priv.strip() == "":
		return ("That's not a valid privilege (%s)." % priv, 400)
	return None

def add_remove_mail_user_privilege(email, priv, action, env):
	# validate
	validation = validate_privilege(priv)
	if validation: return validation

	# get existing privs, but may fail
	privs = get_mail_user_privileges(email, env)
	if isinstance(privs, tuple): return privs # error

	# update privs set
	if action == "add":
		if priv not in privs:
			privs.append(priv)
	elif action == "remove":
		privs = [p for p in privs if p != priv]
	else:
		return ("Invalid action.", 400)

	# commit to database
	conn, c = open_database(env, with_connection=True)
	c.execute("UPDATE users SET privileges=? WHERE email=?", ("\n".join(privs), email))
	if c.rowcount != 1:
		return ("Something went wrong.", 400)
	conn.commit()

	return "OK"

def add_mail_alias(source, destination, env, update_if_exists=False, do_kick=True):
	# validate source
	if source.strip() == "":
		return ("No incoming email address provided.", 400)
	if not validate_email(source, mode='alias'):
		return ("Invalid incoming email address (%s)." % source, 400)

	# parse comma and \n-separated destination emails & validate
	dests = []
	for line in destination.split("\n"):
		for email in line.split(","):
			email = email.strip()
			if email == "": continue
			if not validate_email(email, mode='alias'):
				return ("Invalid destination email address (%s)." % email, 400)
			dests.append(email)
	if len(destination) == 0:
		return ("No destination email address(es) provided.", 400)
	destination = ",".join(dests)

	conn, c = open_database(env, with_connection=True)
	try:
		c.execute("INSERT INTO aliases (source, destination) VALUES (?, ?)", (source, destination))
		return_status = "alias added"
	except sqlite3.IntegrityError:
		if not update_if_exists:
			return ("Alias already exists (%s)." % source, 400)
		else:
			c.execute("UPDATE aliases SET destination = ? WHERE source = ?", (destination, source))
			return_status = "alias updated"

	conn.commit()

	if do_kick:
		# Update things in case any new domains are added.
		return kick(env, return_status)

def remove_mail_alias(source, env, do_kick=True):
	conn, c = open_database(env, with_connection=True)
	c.execute("DELETE FROM aliases WHERE source=?", (source,))
	if c.rowcount != 1:
		return ("That's not an alias (%s)." % source, 400)
	conn.commit()

	if do_kick:
		# Update things in case any domains are removed.
		return kick(env, "alias removed")

def get_system_administrator(env):
	return "administrator@" + env['PRIMARY_HOSTNAME']

def get_required_aliases(env):
	# These are the aliases that must exist.
	aliases = set()

	# The hostmaster alias is exposed in the DNS SOA for each zone.
	aliases.add("hostmaster@" + env['PRIMARY_HOSTNAME'])

	# Get a list of domains we serve mail for, except ones for which the only
	# email on that domain is a postmaster/admin alias to the administrator.
	real_mail_domains = get_mail_domains(env,
		filter_aliases = lambda alias : \
			(not alias[0].startswith("postmaster@") \
			 and not alias[0].startswith("admin@")) \
			or alias[1] != get_system_administrator(env) \
			)

	# Create postmaster@ and admin@ for all domains we serve mail on.
	# postmaster@ is assumed to exist by our Postfix configuration. admin@
	# isn't anything, but it might save the user some trouble e.g. when
	# buying an SSL certificate.
	for domain in real_mail_domains:
		aliases.add("postmaster@" + domain)
		aliases.add("admin@" + domain)

	return aliases

def kick(env, mail_result=None):
	results = []

	# Inclde the current operation's result in output.

	if mail_result is not None:
		results.append(mail_result + "\n")

	# Ensure every required alias exists.

	existing_users = get_mail_users(env)
	existing_aliases = get_mail_aliases(env)
	required_aliases = get_required_aliases(env)

	def ensure_admin_alias_exists(source):
		# If a user account exists with that address, we're good.
		if source in existing_users:
			return

		# Does this alias exists?
		for s, t in existing_aliases:
			if s == source:
				return
		# Doesn't exist.
		administrator = get_system_administrator(env)
		add_mail_alias(source, administrator, env, do_kick=False)
		results.append("added alias %s (=> %s)\n" % (source, administrator))


	for alias in required_aliases:
		ensure_admin_alias_exists(alias)

	# Remove auto-generated postmaster/admin on domains we no
	# longer have any other email addresses for.
	for source, target in existing_aliases:
		user, domain = source.split("@")
		if user in ("postmaster", "admin") \
			and source not in required_aliases \
			and target == get_system_administrator(env):
			remove_mail_alias(source, env, do_kick=False)
			results.append("removed alias %s (was to %s; domain no longer used for email)\n" % (source, target))

	# Update DNS and nginx in case any domains are added/removed.

	from dns_update import do_dns_update
	results.append( do_dns_update(env) )

	from web_update import do_web_update
	results.append( do_web_update(env) )

	return "".join(s for s in results if s != "")

def validate_password(pw):
	# validate password
	if pw.strip() == "":
		raise ValueError("No password provided.")
	if re.search(r"[\s]", pw):
		raise ValueError("Passwords cannot contain spaces.")
	if len(pw) < 4:
		raise ValueError("Passwords must be at least four characters.")


if __name__ == "__main__":
	import sys
	if len(sys.argv) > 2 and sys.argv[1] == "validate-email":
		# Validate that we can create a Dovecot account for a given string.
		if validate_email(sys.argv[2], mode='user'):
			sys.exit(0)
		else:
			sys.exit(1)

	if len(sys.argv) > 1 and sys.argv[1] == "update":
		from utils import load_environment
		print(kick(load_environment()))
