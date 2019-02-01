#!/usr/local/lib/mailinabox/env/bin/python

# NOTE:
# This script is run both using the system-wide Python 3
# interpreter (/usr/bin/python3) as well as through the
# virtualenv (/usr/local/lib/mailinabox/env). So only
# import packages at the top level of this script that
# are installed in *both* contexts. We use the system-wide
# Python 3 in setup/questions.sh to validate the email
# address entered by the user.

import subprocess, shutil, os, sqlite3, re
import utils
from email_validator import validate_email as validate_email_, EmailNotValidError
import idna

def validate_email(email, mode=None):
	# Checks that an email address is syntactically valid. Returns True/False.
	# Until Postfix supports SMTPUTF8, an email address may contain ASCII
	# characters only; IDNs must be IDNA-encoded.
	#
	# When mode=="user", we're checking that this can be a user account name.
	# Dovecot has tighter restrictions - letters, numbers, underscore, and
	# dash only!
	#
	# When mode=="alias", we're allowing anything that can be in a Postfix
	# alias table, i.e. omitting the local part ("@domain.tld") is OK.

	# Check the syntax of the address.
	try:
		validate_email_(email,
			allow_smtputf8=False,
			check_deliverability=False,
			allow_empty_local=(mode=="alias")
			)
	except EmailNotValidError:
		return False

	if mode == 'user':
		# There are a lot of characters permitted in email addresses, but
		# Dovecot's sqlite auth driver seems to get confused if there are any
		# unusual characters in the address. Bah. Also note that since
		# the mailbox path name is based on the email address, the address
		# shouldn't be absurdly long and must not have a forward slash.
		# Our database is case sensitive (oops), which affects mail delivery
		# (Postfix always queries in lowercase?), so also only permit lowercase
		# letters.
		if len(email) > 255: return False
		if re.search(r'[^\@\.a-z0-9_\-]+', email):
			return False

	# Everything looks good.
	return True

def sanitize_idn_email_address(email):
	# The user may enter Unicode in an email address. Convert the domain part
	# to IDNA before going into our database. Leave the local part alone ---
	# although validate_email will reject non-ASCII characters.
	#
	# The domain name system only exists in ASCII, so it doesn't make sense
	# to store domain names in Unicode. We want to store what is meaningful
	# to the underlying protocols.
	try:
		localpart, domainpart = email.split("@")
		domainpart = idna.encode(domainpart).decode('ascii')
		return localpart + "@" + domainpart
	except (ValueError, idna.IDNAError):
		# ValueError: String does not have a single @-sign, so it is not
		# a valid email address. IDNAError: Domain part is not IDNA-valid.
		# Validation is not this function's job, so return value unchanged.
		# If there are non-ASCII characters it will be filtered out by
		# validate_email.
		return email

def prettify_idn_email_address(email):
	# This is the opposite of sanitize_idn_email_address. We store domain
	# names in IDNA in the database, but we want to show Unicode to the user.
	try:
		localpart, domainpart = email.split("@")
		domainpart = idna.decode(domainpart.encode("ascii"))
		return localpart + "@" + domainpart
	except (ValueError, UnicodeError, idna.IDNAError):
		# Failed to decode IDNA, or the email address does not have a
		# single @-sign. Should never happen.
		return email

def is_dcv_address(email):
	email = email.lower()
	for localpart in ("admin", "administrator", "postmaster", "hostmaster", "webmaster", "abuse"):
		if email.startswith(localpart+"@") or email.startswith(localpart+"+"):
			return True
	return False

def open_database(env, with_connection=False):
	conn = sqlite3.connect(env["STORAGE_ROOT"] + "/mail/users.sqlite")
	if not with_connection:
		return conn.cursor()
	else:
		return conn, conn.cursor()

def get_mail_users(env):
	# Returns a flat, sorted list of all user accounts.
	c = open_database(env)
	c.execute('SELECT email FROM users')
	users = [ row[0] for row in c.fetchall() ]
	return utils.sort_email_addresses(users, env)

def sizeof_fmt(num):
	for unit in ['','K','M','G','T']:
		if abs(num) < 1024.0:
			if abs(num) > 99:
				return "%3.0f%s" % (num, unit)
			else:
				return "%2.1f%s" % (num, unit)

		num /= 1024.0

	return str(num)

def get_mail_users_ex(env, with_archived=False):
	# Returns a complex data structure of all user accounts, optionally
	# including archived (status="inactive") accounts.
	#
	# [
	#   {
	#     domain: "domain.tld",
	#     users: [
	#       {
	#         email: "name@domain.tld",
	#         privileges: [ "priv1", "priv2", ... ],
	#         status: "active" | "inactive",
	#       },
	#       ...
	#     ]
	#   },
	#   ...
	# ]

	# Get users and their privileges.
	users = []
	active_accounts = set()
	c = open_database(env)
	c.execute('SELECT email, privileges, quota FROM users')
	for email, privileges, quota in c.fetchall():
		active_accounts.add(email)

		(user, domain) = email.split('@')
		box_size = 0
		box_count = 0
		box_quota = 0
		percent = ''
		try:
			dirsize_file = os.path.join(env['STORAGE_ROOT'], 'mail/mailboxes/%s/%s/maildirsize' % (domain, user))
			with open(dirsize_file, 'r') as f:
				box_quota = int(f.readline().split('S')[0])
				for line in f.readlines():
					(size, count) = line.split(' ')
					box_size += int(size)
					box_count += int(count)

			try:
				percent = (box_size / box_quota) * 100
			except:
				percent = 'Error'

		except:
			box_size = '?'
			box_count = '?'
			box_quota = '?'
			percent = '?'

		if quota == '0':
			percent = ''

		user = {
			"email": email,
			"privileges": parse_privs(privileges),
            "quota": quota,
			"box_quota": box_quota,
			"box_size": sizeof_fmt(box_size) if box_size != '?' else box_size,
			"percent": '%3.0f%%' % percent if type(percent) != str else percent,
			"box_count": box_count,
			"status": "active",
		}
		users.append(user)

	# Add in archived accounts.
	if with_archived:
		root = os.path.join(env['STORAGE_ROOT'], 'mail/mailboxes')
		for domain in os.listdir(root):
			if os.path.isdir(os.path.join(root, domain)):
				for user in os.listdir(os.path.join(root, domain)):
					email = user + "@" + domain
					mbox = os.path.join(root, domain, user)
					if email in active_accounts: continue
					user = {
						"email": email,
						"privileges": "",
						"status": "inactive",
						"mailbox": mbox,
					}
					users.append(user)

	# Group by domain.
	domains = { }
	for user in users:
		domain = get_domain(user["email"])
		if domain not in domains:
			domains[domain] = {
				"domain": domain,
				"users": []
				}
		domains[domain]["users"].append(user)

	# Sort domains.
	domains = [domains[domain] for domain in utils.sort_domains(domains.keys(), env)]

	# Sort users within each domain first by status then lexicographically by email address.
	for domain in domains:
		domain["users"].sort(key = lambda user : (user["status"] != "active", user["email"]))

	return domains

def get_admins(env):
	# Returns a set of users with admin privileges.
	users = set()
	for domain in get_mail_users_ex(env):
		for user in domain["users"]:
			if "admin" in user["privileges"]:
				users.add(user["email"])
	return users

def get_mail_aliases(env):
	# Returns a sorted list of tuples of (address, forward-tos, permitted-senders).
	c = open_database(env)
	c.execute('SELECT source, destination, permitted_senders FROM aliases')
	aliases = { row[0]: row for row in c.fetchall() } # make dict

	# put in a canonical order: sort by domain, then by email address lexicographically
	aliases = [ aliases[address] for address in utils.sort_email_addresses(aliases.keys(), env) ]
	return aliases

def get_mail_aliases_ex(env):
	# Returns a complex data structure of all mail aliases, similar
	# to get_mail_users_ex.
	#
	# [
	#   {
	#     domain: "domain.tld",
	#     alias: [
	#       {
	#         address: "name@domain.tld", # IDNA-encoded
	#         address_display: "name@domain.tld", # full Unicode
	#         forwards_to: ["user1@domain.com", "receiver-only1@domain.com", ...],
	#         permitted_senders: ["user1@domain.com", "sender-only1@domain.com", ...] OR null,
	#         required: True|False
	#       },
	#       ...
	#     ]
	#   },
	#   ...
	# ]

	required_aliases = get_required_aliases(env)
	domains = {}
	for address, forwards_to, permitted_senders in get_mail_aliases(env):
		# get alias info
		domain = get_domain(address)
		required = (address in required_aliases)

		# add to list
		if not domain in domains:
			domains[domain] = {
				"domain": domain,
				"aliases": [],
			}
		domains[domain]["aliases"].append({
			"address": address,
			"address_display": prettify_idn_email_address(address),
			"forwards_to": [prettify_idn_email_address(r.strip()) for r in forwards_to.split(",")],
			"permitted_senders": [prettify_idn_email_address(s.strip()) for s in permitted_senders.split(",")] if permitted_senders is not None else None,
			"required": required,
		})

	# Sort domains.
	domains = [domains[domain] for domain in utils.sort_domains(domains.keys(), env)]

	# Sort aliases within each domain first by required-ness then lexicographically by address.
	for domain in domains:
		domain["aliases"].sort(key = lambda alias : (alias["required"], alias["address"]))
	return domains

def get_domain(emailaddr, as_unicode=True):
	# Gets the domain part of an email address. Turns IDNA
	# back to Unicode for display.
	ret = emailaddr.split('@', 1)[1]
	if as_unicode:
		try:
			ret = idna.decode(ret.encode('ascii'))
		except (ValueError, UnicodeError, idna.IDNAError):
			# Looks like we have an invalid email address in
			# the database. Now is not the time to complain.
			pass
	return ret

def get_mail_domains(env, filter_aliases=lambda alias : True):
	# Returns the domain names (IDNA-encoded) of all of the email addresses
	# configured on the system.
	return set(
		   [get_domain(login, as_unicode=False) for login in get_mail_users(env)]
		 + [get_domain(address, as_unicode=False) for address, *_ in get_mail_aliases(env) if filter_aliases(address) ]
		 )

def add_mail_user(email, pw, privs, quota, env):
	# validate email
	if email.strip() == "":
		return ("No email address provided.", 400)
	elif not validate_email(email):
		return ("Invalid email address.", 400)
	elif not validate_email(email, mode='user'):
		return ("User account email addresses may only use the lowercase ASCII letters a-z, the digits 0-9, underscore (_), hyphen (-), and period (.).", 400)
	elif is_dcv_address(email) and len(get_mail_users(env)) > 0:
		# Make domain control validation hijacking a little harder to mess up by preventing the usual
		# addresses used for DCV from being user accounts. Except let it be the first account because
		# during box setup the user won't know the rules.
		return ("You may not make a user account for that address because it is frequently used for domain control validation. Use an alias instead if necessary.", 400)

	# validate password
	validate_password(pw)

	# validate privileges
	if privs is None or privs.strip() == "":
		privs = []
	else:
		privs = privs.split("\n")
		for p in privs:
			validation = validate_privilege(p)
			if validation: return validation

	if quota is None:
		quota = get_default_quota()

	try:
		quota = validate_quota(quota)
	except ValueError as e:
		return (str(e), 400)

	# get the database
	conn, c = open_database(env, with_connection=True)

	# hash the password
	pw = hash_password(pw)

	# add the user to the database
	try:
		c.execute("INSERT INTO users (email, password, privileges, quota) VALUES (?, ?, ?, ?)",
			(email, pw, "\n".join(privs), quota))
	except sqlite3.IntegrityError:
		return ("User already exists.", 400)

	# write databasebefore next step
	conn.commit()

	# Update things in case any new domains are added.
	return kick(env, "mail user added")

def set_mail_password(email, pw, env):
	# validate that password is acceptable
	validate_password(pw)

	# hash the password
	pw = hash_password(pw)

	# update the database
	conn, c = open_database(env, with_connection=True)
	c.execute("UPDATE users SET password=? WHERE email=?", (pw, email))
	if c.rowcount != 1:
		return ("That's not a user (%s)." % email, 400)
	conn.commit()
	return "OK"

def hash_password(pw):
	# Turn the plain password into a Dovecot-format hashed password, meaning
	# something like "{SCHEME}hashedpassworddata".
	# http://wiki2.dovecot.org/Authentication/PasswordSchemes
	return utils.shell('check_output', ["/usr/bin/doveadm", "pw", "-s", "SHA512-CRYPT", "-p", pw]).strip()

def get_mail_quota(email, env):
	conn, c = open_database(env, with_connection=True)
	c.execute("SELECT quota FROM users WHERE email=?", (email,))
	rows = c.fetchall()
	if len(rows) != 1:
		return ("That's not a user (%s)." % email, 400)

	return rows[0][0]

def set_mail_quota(email, quota, env):
    # validate that password is acceptable
    quota = validate_quota(quota)

    # update the database
    conn, c = open_database(env, with_connection=True)
    c.execute("UPDATE users SET quota=? WHERE email=?", (quota, email))
    if c.rowcount != 1:
        return ("That's not a user (%s)." % email, 400)
    conn.commit()
    return "OK"

def get_default_quota(env):
	config = utils.load_settings(env)
	return config.get("default-quota", '0')

def validate_quota(quota):
    # validate quota
    quota = quota.strip().upper()

    if quota == "":
        raise ValueError("No quota provided.")
    if re.search(r"[\s,]", quota):
        raise ValueError("Quotas cannot contain spaces or commas.")
    if not re.match(r'^[\d\.]+[GM]?$', quota):
        raise ValueError("Invalid quota.")

    return quota

def get_mail_password(email, env):
	# Gets the hashed password for a user. Passwords are stored in Dovecot's
	# password format, with a prefixed scheme.
	# http://wiki2.dovecot.org/Authentication/PasswordSchemes
	# update the database
	c = open_database(env)
	c.execute('SELECT password FROM users WHERE email=?', (email,))
	rows = c.fetchall()
	if len(rows) != 1:
		raise ValueError("That's not a user (%s)." % email)
	return rows[0][0]

def remove_mail_user(email, env):
	# remove
	conn, c = open_database(env, with_connection=True)
	c.execute("DELETE FROM users WHERE email=?", (email,))
	if c.rowcount != 1:
		return ("That's not a user (%s)." % email, 400)
	conn.commit()

	# Update things in case any domains are removed.
	return kick(env, "mail user removed")

def parse_privs(value):
	return [p for p in value.split("\n") if p.strip() != ""]

def get_mail_user_privileges(email, env, empty_on_error=False):
	# get privs
	c = open_database(env)
	c.execute('SELECT privileges FROM users WHERE email=?', (email,))
	rows = c.fetchall()
	if len(rows) != 1:
		if empty_on_error: return []
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

def add_mail_alias(address, forwards_to, permitted_senders, env, update_if_exists=False, do_kick=True):
	# convert Unicode domain to IDNA
	address = sanitize_idn_email_address(address)

	# Our database is case sensitive (oops), which affects mail delivery
	# (Postfix always queries in lowercase?), so force lowercase.
	address = address.lower()

	# validate address
	address = address.strip()
	if address == "":
		return ("No email address provided.", 400)
	if not validate_email(address, mode='alias'):
		return ("Invalid email address (%s)." % address, 400)

	# validate forwards_to
	validated_forwards_to = []
	forwards_to = forwards_to.strip()

	# extra checks for email addresses used in domain control validation
	is_dcv_source = is_dcv_address(address)

	# Postfix allows a single @domain.tld as the destination, which means
	# the local part on the address is preserved in the rewrite. We must
	# try to convert Unicode to IDNA first before validating that it's a
	# legitimate alias address. Don't allow this sort of rewriting for
	# DCV source addresses.
	r1 = sanitize_idn_email_address(forwards_to)
	if validate_email(r1, mode='alias') and not is_dcv_source:
		validated_forwards_to.append(r1)

	else:
		# Parse comma and \n-separated destination emails & validate. In this
		# case, the forwards_to must be complete email addresses.
		for line in forwards_to.split("\n"):
			for email in line.split(","):
				email = email.strip()
				if email == "": continue
				email = sanitize_idn_email_address(email) # Unicode => IDNA
				# Strip any +tag from email alias and check privileges
				privileged_email = re.sub(r"(?=\+)[^@]*(?=@)",'',email)
				if not validate_email(email):
					return ("Invalid receiver email address (%s)." % email, 400)
				if is_dcv_source and not is_dcv_address(email) and "admin" not in get_mail_user_privileges(privileged_email, env, empty_on_error=True):
					# Make domain control validation hijacking a little harder to mess up by
					# requiring aliases for email addresses typically used in DCV to forward
					# only to accounts that are administrators on this system.
					return ("This alias can only have administrators of this system as destinations because the address is frequently used for domain control validation.", 400)
				validated_forwards_to.append(email)

	# validate permitted_senders
	valid_logins = get_mail_users(env)
	validated_permitted_senders = []
	permitted_senders = permitted_senders.strip()

	# Parse comma and \n-separated sender logins & validate. The permitted_senders must be
	# valid usernames.
	for line in permitted_senders.split("\n"):
		for login in line.split(","):
			login = login.strip()
			if login == "": continue
			if login not in valid_logins:
				return ("Invalid permitted sender: %s is not a user on this system." % login, 400)
			validated_permitted_senders.append(login)

	# Make sure the alias has either a forwards_to or a permitted_sender.
	if len(validated_forwards_to) + len(validated_permitted_senders) == 0:
		return ("The alias must either forward to an address or have a permitted sender.", 400)

	# save to db

	forwards_to = ",".join(validated_forwards_to)

	if len(validated_permitted_senders) == 0:
		permitted_senders = None
	else:
		permitted_senders = ",".join(validated_permitted_senders)

	conn, c = open_database(env, with_connection=True)
	try:
		c.execute("INSERT INTO aliases (source, destination, permitted_senders) VALUES (?, ?, ?)", (address, forwards_to, permitted_senders))
		return_status = "alias added"
	except sqlite3.IntegrityError:
		if not update_if_exists:
			return ("Alias already exists (%s)." % address, 400)
		else:
			c.execute("UPDATE aliases SET destination = ?, permitted_senders = ? WHERE source = ?", (forwards_to, permitted_senders, address))
			return_status = "alias updated"

	conn.commit()

	if do_kick:
		# Update things in case any new domains are added.
		return kick(env, return_status)

def remove_mail_alias(address, env, do_kick=True):
	# convert Unicode domain to IDNA
	address = sanitize_idn_email_address(address)

	# remove
	conn, c = open_database(env, with_connection=True)
	c.execute("DELETE FROM aliases WHERE source=?", (address,))
	if c.rowcount != 1:
		return ("That's not an alias (%s)." % address, 400)
	conn.commit()

	if do_kick:
		# Update things in case any domains are removed.
		return kick(env, "alias removed")

def get_system_administrator(env):
	return "administrator@" + env['PRIMARY_HOSTNAME']

def get_required_aliases(env):
	# These are the aliases that must exist.
	aliases = set()

	# The system administrator alias is required.
	aliases.add(get_system_administrator(env))

	# The hostmaster alias is exposed in the DNS SOA for each zone.
	aliases.add("hostmaster@" + env['PRIMARY_HOSTNAME'])

	# Get a list of domains we serve mail for, except ones for which the only
	# email on that domain are the required aliases or a catch-all/domain-forwarder.
	real_mail_domains = get_mail_domains(env,
		filter_aliases = lambda alias :
			not alias.startswith("postmaster@")
			and not alias.startswith("admin@")
			and not alias.startswith("abuse@")
			and not alias.startswith("@")
			)

	# Create postmaster@, admin@ and abuse@ for all domains we serve
	# mail on. postmaster@ is assumed to exist by our Postfix configuration.
	# admin@isn't anything, but it might save the user some trouble e.g. when
	# buying an SSL certificate.
	# abuse@ is part of RFC2142: https://www.ietf.org/rfc/rfc2142.txt
	for domain in real_mail_domains:
		aliases.add("postmaster@" + domain)
		aliases.add("admin@" + domain)
		aliases.add("abuse@" + domain)

	return aliases

def kick(env, mail_result=None):
	results = []

	# Include the current operation's result in output.

	if mail_result is not None:
		results.append(mail_result + "\n")

	# Ensure every required alias exists.

	existing_users = get_mail_users(env)
	existing_alias_records = get_mail_aliases(env)
	existing_aliases = set(a for a, *_ in existing_alias_records) # just first entry in tuple
	required_aliases = get_required_aliases(env)

	def ensure_admin_alias_exists(address):
		# If a user account exists with that address, we're good.
		if address in existing_users:
			return

		# If the alias already exists, we're good.
		if address in existing_aliases:
			return

		# Doesn't exist.
		administrator = get_system_administrator(env)
		if address == administrator: return # don't make an alias from the administrator to itself --- this alias must be created manually
		add_mail_alias(address, administrator, "", env, do_kick=False)
		if administrator not in existing_aliases: return # don't report the alias in output if the administrator alias isn't in yet -- this is a hack to supress confusing output on initial setup
		results.append("added alias %s (=> %s)\n" % (address, administrator))

	for address in required_aliases:
		ensure_admin_alias_exists(address)

	# Remove auto-generated postmaster/admin on domains we no
	# longer have any other email addresses for.
	for address, forwards_to, *_ in existing_alias_records:
		user, domain = address.split("@")
		if user in ("postmaster", "admin", "abuse") \
			and address not in required_aliases \
			and forwards_to == get_system_administrator(env):
			remove_mail_alias(address, env, do_kick=False)
			results.append("removed alias %s (was to %s; domain no longer used for email)\n" % (address, forwards_to))

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
	if len(pw) < 8:
		raise ValueError("Passwords must be at least eight characters.")


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
