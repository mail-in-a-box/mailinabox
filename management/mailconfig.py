#!/usr/local/lib/mailinabox/env/bin/python
# -*- indent-tabs-mode: t; tab-width: 4; python-indent-offset: 4; -*-

# NOTE:
# This script is run both using the system-wide Python 3
# interpreter (/usr/bin/python3) as well as through the
# virtualenv (/usr/local/lib/mailinabox/env). So only
# import packages at the top level of this script that
# are installed in *both* contexts. We use the system-wide
# Python 3 in setup/questions.sh to validate the email
# address entered by the user.

import subprocess, shutil, os, sqlite3, re, ldap3, uuid, hashlib
import utils, backend
from email_validator import validate_email as validate_email_, EmailNotValidError
import idna


#
# LDAP notes:
#
#    Users have an objectClass of mailUser with a mail and maildrop
#    attribute for the email address. For historical reasons, the
#    management interface only permits lowercase email addresses.
#
#    In the current implementation, both attributes will have the same
#    lowercase value, but it's not a requirement of the underlying
#    postfix and dovecot configurations that it be this way. Postfix
#    and dovecot use the mail attribute to find the user and maildrop
#    is where the mail is delivered. We use maildrop in the management
#    interface because that's the address that will always map
#    directly to the filesystem for archived users.
#
#    Email addresses and domain comparisons performed by the LDAP
#    server are not case sensitive because their respective schemas
#    define a case-insensitive comparison for those attributes.
#
#    User privileges are maintained in the mailaccess attribute of
#    users.
#
#    Aliases and permitted-senders are separate entities in the LDAP
#    database, but both are of objectClass mailGroup with a
#    single-valued mail attribute. Alias addresses are forced to
#    lowercase, again for historical reasons.
#
#    All alias and permitted-sender email addresses in the database
#    are IDNA encoded. International domains for users is not
#    supported or permitted.
#
#    Domains that are handled by this mail server are maintained
#    on-the-fly as users are added and deleted. They have an
#    objectClass of domain with attribute dc.
#
#    LDAP "records" in this code are dictionaries containing the
#    attributes and distinguished name of the entry.
#

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

def open_database(env):
		return backend.connect(env)

def find_mail_user(env, email, attributes=None, conn=None):
	# Find the user with the given email address and return the ldap
	# record for it.
	#
	# email is the users email address
	# attributes are a list of attributes to return eg ["mail","maildrop"]
	# conn is a ldap database connection, if not specified a new one
	# is established	
	#
	# The ldap record for the user is returned or None if not found.
	if not conn: conn = open_database(env)
	id=conn.search(env.LDAP_USERS_BASE,
		       "(&(objectClass=mailUser)(maildrop=%s))" % email,
		       attributes=attributes)
	response = conn.wait(id)
	if response.count() > 1:
		dns = [ rec['dn'] for rec in response ]
		raise LookupError("Detected more than one user with the same email address (%s): %s" % (email, ";".join(dns)))
	else:
		return response.next()
	
def find_mail_alias(env, email, attributes=None, conn=None):
	# Find the alias with the given address and return the ldap
	# records for it and the associated permitted senders (if one).
	#
	# email is the alias address. It must be IDNA encoded.
	#
	# attributes are a list of attributes to return, eg
	# ["member","rfc822MailMember"]
	#
	# conn is a ldap database connection, if not specified a new one
	# is established.
	#
	# A tuple having the two ldap records for the alias and it's
	# permitted senders (alias, permitted_senders) is returned. If
	# either is not found, the corresponding tuple value will be None.
	# 
	if not conn: conn = open_database(env)
	# get alias
	id=conn.search(env.LDAP_ALIASES_BASE,
		       "(&(objectClass=mailGroup)(mail=%s))" % email,
		       attributes=attributes)
	response = conn.wait(id)
	if response.count() > 1:
		dns = [ rec['dn'] for rec in response ]
		raise LookupError("Detected more than one alias with the same email address (%s): %s" % (email, ";".join(dns)))
	alias = response.next()

	# get permitted senders for alias
	id=conn.search(env.LDAP_PERMITTED_SENDERS_BASE,
		       "(&(objectClass=mailGroup)(mail=%s))" % email,
		       attributes=attributes)
	response = conn.wait(id)
	if response.count() > 1:
		dns = [ rec['dn'] for rec in response ]
		raise LookupError("Detected more than one permitted senders group with the same email address (%s): %s" % (email, ";".join(dns)))
	permitted_senders = response.next()
	return (alias, permitted_senders)
	

def get_mail_users(env, as_map=False):
	# When `as_map` is False, this function returns a flat, sorted
	# array of all user accounts. If True, it returns a dict where key
	# is the user and value is a dict having, dn, maildrop and
	# mail addresses
	c = open_database(env)
	pager = c.paged_search(env.LDAP_USERS_BASE, "(objectClass=mailUser)", attributes=['maildrop','mail','cn'])
	if as_map:
		users = {}
		for rec in pager:
			users[rec['maildrop'][0]] = {
				"dn":   rec['dn'],
				"mail": rec['mail'],
				"maildrop": rec['maildrop'][0],
				"display_name": rec['cn'][0]
			}
		return users
	else:
		users = [ rec['maildrop'][0] for rec in pager ]
		return utils.sort_email_addresses(users, env)

	
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
	#         display_name: ""
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
	response = c.wait( c.search(env.LDAP_USERS_BASE, "(objectClass=mailUser)", attributes=['maildrop','mailaccess','cn']) )

	for rec in response:
		email = rec['maildrop'][0]
		privileges = rec['mailaccess']
		display_name = rec['cn'][0]
		active_accounts.add(email)
		user = {
			"email": email,
			"privileges": privileges,
			"status": "active",
			"display_name": display_name
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
						"privileges": [],
						"status": "inactive",
						"mailbox": mbox,
						"display_name": ""
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
	c = open_database(env)
	response = c.wait( c.search(env.LDAP_USERS_BASE, "(&(objectClass=mailUser)(mailaccess=admin))", attributes=['maildrop']) )
	for rec in response:
		users.add(rec['maildrop'][0])
	return users


def get_mail_aliases(env, as_map=False):
	# Retrieve all mail aliases.
	#
	# If as_map is False, the function returns a sorted array of tuples:
	#
	#   (address(lowercase), forward-tos{string,csv}, permitted-senders{string,csv})
	#
	# If as-map is True, it returns a dict whose keys are
	# address(lowercase) and whose values are:
	#
	#    { dn: {string},
	#      mail: {string}
	#      forward_tos: {array of string},
	#      permited_senders: {array of string},
	#      description: {string}
	#    }
	#
	c = open_database(env)
	# get all permitted senders
	pager = c.paged_search(env.LDAP_PERMITTED_SENDERS_BASE, "(objectClass=mailGroup)", attributes=["mail", "member"])
	
	# make a dict of permitted senders, key=mail(lowercase) value=members
	permitted_senders = { rec["mail"][0].lower(): rec["member"] for rec in pager }

	# get all alias groups
	pager = c.paged_search(env.LDAP_ALIASES_BASE, "(objectClass=mailGroup)", attributes=['mail','member','rfc822MailMember', 'description'])
	
	# make a dict of aliases
	# key=email(lowercase), value=(email, forward-tos, permitted-senders).
	aliases = {}
	for alias in pager:
		alias_email = alias['mail'][0]
		alias_email_lc = alias_email.lower()
		
		# chase down each member's email address, because a member is a dn
		forward_tos = []
		for fwd_to in c.chase_members(alias['member'], 'mail', env):
			forward_tos.append(fwd_to[0])
			
		for fwd_to in alias['rfc822MailMember']:
			forward_tos.append(fwd_to)
		
		# chase down permitted senders' email addresses
		allowed_senders = []
		if alias_email_lc in permitted_senders:
			members = permitted_senders[alias_email_lc]
			for mail_list in c.chase_members(members, 'mail', env):
				for mail in mail_list:
					allowed_senders.append(mail)

		aliases[alias_email_lc] = {
			"dn": alias["dn"],
			"mail": alias_email,
			"forward_tos": forward_tos,
			"permitted_senders": allowed_senders,
			"description": alias["description"][0]
		}

	if not as_map:
		# put in a canonical order: sort by domain, then by email address lexicographically
		list = []
		for address in utils.sort_email_addresses(aliases.keys(), env):
			alias = aliases[address]
			xft = ",".join(alias["forward_tos"])
			xas = ",".join(alias["permitted_senders"])
			list.append( (address, xft, None if xas == "" else xas) )
		return list
	
	else:
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
	#         required: True|False,
	#         description: ""
	#       },
	#       ...
	#     ]
	#   },
	#   ...
	# ]

	aliases=get_mail_aliases(env, as_map=True)
	required_aliases = get_required_aliases(env)
	domains = {}
	
	for alias_lc in aliases:
		alias=aliases[alias_lc]
		address=alias_lc
		
		# get alias info
		forwards_to=alias["forward_tos"]
		permitted_senders=alias["permitted_senders"]
		description=alias["description"]
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
			"forwards_to": [prettify_idn_email_address(r.strip()) for r in forwards_to],
			"permitted_senders": [prettify_idn_email_address(s.strip()) for s in permitted_senders] if permitted_senders is not None and len(permitted_senders)>0 else None,
			"required": required,
			"description": description
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

def get_mail_domains(env, as_map=False, filter_aliases=lambda alias: True, category=None, users_only=False):
	# Retrieves all domains, IDNA-encoded, we accept mail for.
	#
	# If as_map is False, the function returns the lowercase domain
	# names (IDNA-encoded) as an array.
	#
	# If as_map is True, it returns a dict whose keys are
	# domain(idna,lowercase) and whose values are:
	#
	#   { dn:{string}, domain:{string(idna)} }
	#
	# filter_aliases is an inclusion filter - a True return value from
	# this lambda function indicates an alias to include.
	#
	# With filter_aliases, there has to be at least one user or
	# filtered (included) alias in the domain for the domain to be
	# part of the returned set. If None, all domains are returned.
	#
	# category is another type of filter. Set to a string value to
	# return only those domains of that category. ie. the
	# "businessCategory" attribute of the domain must include this
	# category. [TODO: this doesn't really belong there, it is here to
	# make it easy for dns_update to get ssl domains]
	#
	# If users_only is True, only return domains with email addresses
	# that correspond to user accounts.
	#
	conn = open_database(env)
	filter = "(&(objectClass=domain)(businessCategory=mail))"
	if category:
		filter = "(&(objectClass=domain)(businessCategory=%s))" % category

	domains=None

	# user mail domains
	id = conn.search(env.LDAP_DOMAINS_BASE, filter, attributes="dc")
	response = conn.wait(id)
	if as_map:
		domains = {}
		for rec in response:
			domains[ rec["dc"][0].lower() ] = {
				"dn": rec["dn"],
				"domain": rec["dc"][0]
			}
			if filter_aliases: filter_candidates.append(rec['dc'][0].lower())
	else:
		domains = set([ rec["dc"][0].lower() for rec in response ])


	# alias domains
	#
	# Ignore aliases that have no forward-to. We don't need DNS
	# handling in that case becuase the alias is there only for the
	# permitted-senders. We don't accept mail locally for the alias.
	#
	# Aliases with only permitted-senders are useful when a server has
	# a configured smarthost (eg. sendmail with a smarthost, or using
	# ssmtp on Ubuntu, etc). The server drops mail off for delivery to
	# the smarthost (MiaB) using its MiaB login but needs to MAIL FROM
	# a host login (user@host.tld). Replies should bounce.
	#
	# A smarthost configuration should be a catch-all, one for each server:
	#   Alias=@host.tld
	#   Forward-to=<blank>
	#   Permitted-senders:<the email that the smarthost used to authenticate with MiaB>
	#
	if not users_only:
		pager = conn.paged_search(env.LDAP_ALIASES_BASE, "(objectClass=mailGroup)", attributes=["mail","member","rfc822MailMember"])
		if as_map:
			for rec in pager:
				if filter_aliases(rec["mail"][0].lower()) and ( len(rec["member"]) >0 or len(rec["rfc822MailMember"]) >0 ):
					domain = get_domain(rec["mail"][0].lower(),as_unicode=False)
					domains[domain] = {
						"dn": None,
						"domain": domain
					}

		else:
			alias_domains = set([
				get_domain(rec["mail"][0].lower(), as_unicode=False)
				for rec in pager if filter_aliases(rec["mail"][0].lower()) and
				( len(rec["member"]) >0 or len(rec["rfc822MailMember"]) >0 )
			])			
			domains = domains.union( alias_domains )
					
	return domains


def add_mail_domain(env, domain, validate=True):
	# Create domain entry indicating that we are handling
	# mail for that domain.
	#
	# We only care about domains for users, not for aliases.
	#
	# domain: IDNA encoded domain name.
	# validate: If True, ensure there is at least one user on the
	# system using that domain.
	#
	# returns True if added, False if it already exists or fails
	# validation.
	
	conn = open_database(env)
	if validate:
		# check to ensure there is at least one user with that domain
		id = conn.search(env.LDAP_USERS_BASE,
						 "(&(objectClass=mailUser)(mail=*@%s))" % domain,
						 size_limit=1)
		if conn.wait(id).count() == 0:
			# no mail users are using that domain!
			return False
		
	dn = 'dc=%s,%s' % (domain, env.LDAP_DOMAINS_BASE)
	try:
		response = conn.wait( conn.add(dn, [ 'domain' ], {
			"businessCategory": "mail"
		}) )
		return True
	except ldap3.core.exceptions.LDAPEntryAlreadyExistsResult:
		try:
			# add 'mail' as a businessCategory
			changes = {	"businessCategory": [(ldap3.MODIFY_ADD, ['mail'])] }
			response = conn.wait ( conn.modify(dn, changes) )
		except ldap3.core.exceptions.LDAPAttributeOrValueExistsResult:
			pass
		return False

	
def remove_mail_domain(env, domain, validate=True):
	# Remove the specified domain from the list of domains that we
	# handle mail for. The domain must be IDNA encoded.
	#
	# If validate is True, ensure there are no valid users on the system
	# currently using the domain.
	#
	# Returns True if removed or does not exist, False if the domain
	# fails validation.
	conn = open_database(env)
	if validate:
		# check to ensure no users are using the domain
		id = conn.search(env.LDAP_USERS_BASE,
						 "(&(objectClass=mailUser)(mail=*@%s))" % domain,
						 size_limit=1)
		if conn.wait(id).count() > 0:
			# there is one or more mailUser's with that domain
			return False
		
	id = conn.search(env.LDAP_DOMAINS_BASE,
					 "(&(objectClass=domain)(dc=%s))" % domain,
					 attributes=['businessCategory'])
	
	existing = conn.wait(id).next()
	if existing is None:
		# the domain doesn't exist!
		return True

	newvals=existing['businessCategory'].copy()
	if 'mail' in newvals:
		newvals.remove('mail')
	else:
		# we only remove mail-related entries
		return False

	if len(newvals)==0:
		conn.wait ( conn.delete(existing['dn']) )
	else:
		conn.wait ( conn.modify_record(existing, {'businessCategory', newvals}))
	return True


def add_mail_user(email, pw, privs, display_name, env):
	# Add a new mail user.
	#
	# email: the new user's email address
	# pw: the new user's password
	# privs: either an array of privilege strings, or a newline
	# separated string of privilege names
	# display_name: a string with users givenname and surname (eg "Al Woods")
	#
	# If an error occurs, the function returns a tuple of (message,
	# http-status).
	#
	# If successful, the string "OK" is returned.
	
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
	privs = []
	if privs is not None and type(privs) is str and privs.strip() != "":
		privs = parse_privs(privs)
	for p in privs:
		validation = validate_privilege(p)
		if validation: return validation

	# get the database
	conn = open_database(env)

	# ensure another user doesn't have that address
	id=conn.search(env.LDAP_USERS_BASE, "(&(objectClass=mailUser)(|(mail=%s)(maildrop=%s)))" % (email, email))
	if conn.wait(id).count() > 0:
		return ("User alreay exists.", 400)

	# ensure an alias doesn't have that address
	id=conn.search(env.LDAP_ALIASES_BASE, "(&(objectClass=mailGroup)(mail=%s))" % email)
	if conn.wait(id).count() > 0:
		return ("An alias exists with that address.", 400)
	
	## Generate a unique id for uid
	#uid = '%s' % uuid.uuid4()
	# use a sha-1 hash of maildrop for uid
	m = hashlib.sha1()
	m.update(bytearray(email.lower(),'utf-8'))
	uid = m.hexdigest()

	# choose a common name and surname (required attributes)
	if display_name:
		cn = display_name
	else:
		cn = email.split("@")[0].replace('.',' ').replace('_',' ')
	sn = cn[cn.find(' ')+1:]
	
	# compile user's attributes
	# for historical reasons, make the email address lowercase
	attrs = {
		"mail" : email,
		"maildrop" : email.lower(),
		"uid" : uid,
		"mailaccess": privs,
		"cn": cn,
		"sn": sn,
		"shadowLastChange": backend.get_shadowLastChanged()
	}

	# add the user to the database
	dn = 'uid=%s,%s' % (uid, env.LDAP_USERS_BASE)
	id=conn.add(dn, [ 'inetOrgPerson','mailUser','shadowAccount' ], attrs);
	conn.wait(id)

	# set the password - the ldap server will hash it
	conn.extend.standard.modify_password(user=dn, new_password=pw)

	# tell postfix the domain is local, if needed
	add_mail_domain(env, get_domain(email, as_unicode=False), validate=False)

	# convert alias's rfc822MailMember to member
	convert_rfc822MailMember(env, conn, dn, email)
	
	# Update things in case any new domains are added.
	return kick(env, "mail user added")

def set_mail_password(email, pw, env):
	# validate that the password is acceptable
	validate_password(pw)

	# find the user				  
	conn = open_database(env)
	user = find_mail_user(env, email, ['shadowLastChange'], conn)
	if user is None:
		return ("That's not a user (%s)." % email, 400)

	# update the database - the ldap server will hash the password
	conn.extend.standard.modify_password(user=user['dn'], new_password=pw)

	# update shadowLastChange
	conn.modify_record(user, {'shadowLastChange': backend.get_shadowLastChanged()})

	return "OK"

def set_mail_display_name(email, display_name, env):
	# validate arguments
	if not display_name or display_name.strip() == "":
		return ("Display name may not be empty!", 400)
	
	# find the user
	conn = open_database(env)
	user = find_mail_user(env, email, ['cn', 'sn'], conn)
	if user is None:
		return ("That's not a user (%s)." % email, 400)

	# update cn and sn
	sn = display_name[display_name.strip().find(' ')+1:]
	conn.modify_record(user, {'cn': display_name.strip(), 'sn': sn})
	
	return "OK"

def validate_login(email, pw, env):
	# Validate that `email` exists and has password `pw`.
	# Returns True if valid, or False if invalid.
	user = find_mail_user(env, email)
	if user is None:
		raise ValueError("That's not a user (%s)" % email)
	try:
		# connect as that user to validate the login
		server = backend.get_ldap_server(env)
		conn = ldap3.Connection(
			server,
			user=user['dn'],
			password=pw,
			raise_exceptions=True)
		conn.bind()
		conn.unbind()
		return True
	except ldap3.core.exceptions.LDAPInvalidCredentialsResult:
		return False


def get_mail_password(email, env):
	# Gets the hashed passwords for a user. In ldap, userPassword is
	# multi-valued and each value can have different hash. This
	# function returns all hashes as an array.
	user = find_mail_user(env, email, attributes=["userPassword"])
	if user is None:
		raise ValueError("That's not a user (%s)." % email)
	if len(user['userPassword'])==0:
		raise ValueError("The user has no password (%s)" % email)
	return user['userPassword']


def remove_mail_user(email, env):
	# Remove the user as a valid user of the system.
	# If an error occurs, the function returns a tuple of (message,
	# http-status).
	#
	# If successful, the string "OK" is returned.
	conn = open_database(env)
	
	# find the user
	user = find_mail_user(env, email, conn=conn)
	if user is None:
		return ("That's not a user (%s)." % email, 400)
	
	# delete the user
	conn.wait( conn.delete(user['dn']) )

	# remove as a handled domain, if needed
	remove_mail_domain(env, get_domain(email, as_unicode=False))

	# Update things in case any domains are removed.
	return kick(env, "mail user removed")

def parse_privs(value):
	return [p for p in value.split("\n") if p.strip() != ""]

def get_mail_user_privileges(email, env, empty_on_error=False):
	# Get an array of privileges held by the specified user.
	c = open_database(env)
	try:
		user = find_mail_user(env, email, ['mailaccess'], c)
	except LookupError as e:
		if empty_on_error: return []
		raise e
	
	if user is None:
		if empty_on_error: return []
		return ("That's not a user (%s)." % email, 400)
	
	return user['mailaccess']

def validate_privilege(priv):
	if "\n" in priv or priv.strip() == "":
		return ("That's not a valid privilege (%s)." % priv, 400)
	return None

def add_remove_mail_user_privilege(email, priv, action, env):
	# Add or remove a privilege from a user.
	# priv: the name of the privilege to add or remove
	# action: "add" to add the privilege, or "remove" to remove it
	# email: the user
	#
	# If an error occurs, the function returns a tuple of (message,
	# http-status).
	#
	# If successful, the string "OK" is returned.
	
	# validate
	validation = validate_privilege(priv)
	if validation: return validation

	# get existing privs, but may fail
	user = find_mail_user(env, email, attributes=['mailaccess'])
	if user is None:
		return ("That's not a user (%s)." % email, 400)
		
	privs = user['mailaccess'].copy()

	# update privs set
	changed = False
	if action == "add":
		if priv not in privs:
			privs.append(priv)
			changed = True
			
	elif action == "remove":
		if priv in privs:
			privs.remove(priv)
			changed = True
	else:
		return ("Invalid action.", 400)

	# commit to database
	if changed:
		conn = open_database(env)
		conn.modify_record( user, {'mailaccess': privs} )
		
	return "OK"



def convert_rfc822MailMember(env, conn, dn, mail):
	# if a newly added alias or user exists as an rfc822MailMember,
	# convert it to a member dn
	# the new alias or user is specified by arguments mail and dn.
	# mail is the new alias or user's email address
	# dn is the new alias or user's distinguished name
	# conn is an existing ldap database connection
	id=conn.search(env.LDAP_ALIASES_BASE,
				   "(&(objectClass=mailGroup)(rfc822MailMember=%s))" % mail,
				   attributes=[ 'member','rfc822MailMember' ])
	response = conn.wait(id)
	for rec in response:
		# remove mail from rfc822MailMember
		changes={ "rfc822MailMember": [(ldap3.MODIFY_DELETE, [mail])] }
		conn.wait( conn.modify(rec['dn'], changes) )

		# add dn to member
		rec['member'].append(dn)
		changes={ "member": [(ldap3.MODIFY_ADD, rec['member'])] }
		try:
			conn.wait( conn.modify(rec['dn'], changes) )
		except ldap3.core.exceptions.LDAPAttributeOrValueExistsResult:
			pass

		
def add_mail_alias(address, description, forwards_to, permitted_senders, env, update_if_exists=False, do_kick=True):
	# Add a new alias group with permitted senders.
	#
	# address: the email address of the alias
	# description: a text description of the alias
	# forwards_to: a string of newline and comma separated email address
	# where mail is delivered
	# permitted_senders: a string of newline and comma separated email addresses of local users that are permitted to MAIL FROM the alias.
	# update_if_exists: if False and the alias exists fail, otherwise update the existing alias with the new values
	#
	# If an error occurs, the function returns a tuple of (message,
	# http-status).
	#
	# If successful, the string "OK" is returned.

	# convert Unicode domain to IDNA
	address = sanitize_idn_email_address(address)

	# for historical reasons, force the address to lowercase
	address = address.lower()

	# validate address
	address = address.strip()
	if address == "":
		return ("No email address provided.", 400)
	if not validate_email(address, mode='alias'):
		return ("Invalid email address (%s)." % address, 400)

	# retrieve all logins as a map ( email.lower() => {mail,dn} )
	valid_logins = get_mail_users( env, as_map=True )
	
	# validate forwards_to
	validated_forwards_to = [ ]
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
	validated_permitted_senders = [ ]  # list of dns
	permitted_senders = permitted_senders.strip( )

	# Parse comma and \n-separated sender logins & validate. The permitted_senders must be
	# valid usernames.
	for line in permitted_senders.split("\n"):
		for login in line.split(","):
			login = login.strip()
			if login == "": continue
			if login.lower() not in valid_logins:
				return ("Invalid permitted sender: %s is not a user on this system." % login, 400)
			validated_permitted_senders.append(valid_logins[login.lower()]['dn'])

	# Make sure the alias has either a forwards_to or a permitted_sender.
	if len(validated_forwards_to) + len(validated_permitted_senders) == 0:
		return ("The alias must either forward to an address or have a permitted sender.", 400)


	# break validated_forwards_to into 'local' where an email
	# address is a local user, or 'remote' where the email doesn't
	# exist on this system

	vfwd_tos_local = []   # list of dn's
	vfwd_tos_remote = []  # list of email
	for fwd_to in validated_forwards_to:
		fwd_to_lc = fwd_to.lower()
		if fwd_to_lc in valid_logins:
			dn = valid_logins[fwd_to_lc]['dn']
			vfwd_tos_local.append(dn)
		else:
			vfwd_tos_remote.append(fwd_to)
			
	# save to db

	conn = open_database(env)
	existing_alias, existing_permitted_senders = find_mail_alias(env, address, ['member','rfc822MailMember', 'description'], conn)
	if existing_alias and not update_if_exists:
		return ("Alias already exists (%s)." % address, 400)
	
	cn="%s" % uuid.uuid4()
	dn="cn=%s,%s" % (cn, env.LDAP_ALIASES_BASE)
	if not description:
		# supply a default description for new entries that did not
		# specify one
		if not existing_alias:
			if address.startswith('@') and \
			   len(validated_forwards_to)==1 and \
			   validated_forwards_to[0].startswith('@'):
				description = "Domain alias %s->%s" % (address, validated_forwards_to[0])
			elif address.startswith('@'):
				description = "Catch-all for %s" % address
			else:
				description ="Mail alias %s" % address
		
		# when updating, ensure the description has a value because
		# the ldap schema does not allow an empty field
		else:
			description=" "
	
	attrs = {
		"mail": address,
		"description": description,
		"member": vfwd_tos_local,
		"rfc822MailMember": vfwd_tos_remote
	}
	
	op = conn.add_or_modify(dn, existing_alias,
			['member', 'rfc822MailMember', 'description' ],
			['mailGroup'],
			attrs)
	if op == 'modify':
		return_status = "alias updated"
	else:
		return_status = "alias added"
		convert_rfc822MailMember(env, conn, dn, address)
		
	# add or modify permitted-senders group
	
	cn = '%s' % uuid.uuid4()
	dn = "cn=%s,%s" % (cn, env.LDAP_PERMITTED_SENDERS_BASE)
	attrs = {
		"mail" : address,
		"description": "Permitted to MAIL FROM this address",
		"member" : validated_permitted_senders
	}
	if len(validated_permitted_senders)==0:
		if existing_permitted_senders:
			dn = existing_permitted_senders['dn']
			conn.wait( conn.delete(dn) )
	else:
		op=conn.add_or_modify(dn, existing_permitted_senders,
							  [ 'member' ], [ 'mailGroup' ],
							  attrs)

	if do_kick:
		# Update things in case any new domains are added.
		return kick(env, return_status)
	

def remove_mail_alias(address, env, do_kick=True):
	# Remove an alias group and it's associated permitted senders
	# group.
	#
	# address is the email address of the alias
	#
	# If an error occurs, the function returns a tuple of (message,
	# http-status).
	#
	# If successful, the string "OK" is returned.
	
	# convert Unicode domain to IDNA
	address = sanitize_idn_email_address(address)

	# remove
	conn = open_database(env)
	existing_alias, existing_permitted_senders = find_mail_alias(env, address, conn=conn)
	if existing_alias:
		conn.delete(existing_alias['dn'])
	else:
		return ("That's not an alias (%s)." % address, 400)

	if existing_permitted_senders:
		conn.delete(existing_permitted_senders['dn'])
		
	if do_kick:
		# Update things in case any domains are removed.
		return kick(env, "alias removed")

def get_system_administrator(env):
	return "administrator@" + env['PRIMARY_HOSTNAME']

def get_required_aliases(env):
	# These are the aliases that must exist.
	# Returns a set of email addresses.
	
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

# multi-factor auth

def get_mfa_state(email, env):
	# find the user				  
	conn = open_database(env)
	user = find_mail_user(env, email, ['objectClass','totpSecret','totpMruToken'], conn)
	if user is None or 'totpUser' not in user['objectClass']:
		return { 'type': None }

	secret = user['totpSecret'][0]
	mru_token = None
	if len(user['totpMruToken'])>0:
		mru_token = user['totpMruToken'][0]

	return {
		'type': 'totp',
		'secret': secret,
		'mru_token': '' if mru_token is None else mru_token
	}

def create_totp_credential(email, secret, env):
	validate_totp_secret(secret)
	conn = open_database(env)
	user = find_mail_user(env, email, ['objectClass','totpSecret'], conn)
	if user is None:
		return ("That's not a user (%s)." % email, 400)

	attrs = {
		"totpSecret": secret,
	}
	if 'totpUser' not in user['objectClass']:
		attrs['objectClass'] = user['objectClass'].copy()
		attrs['objectClass'].append('totpUser')
	conn.add_or_modify(user['dn'], user, attrs.keys(), None, attrs)
	return "OK"

def set_mru_totp_code(email, token, env):
	conn = open_database(env)
	user = find_mail_user(env, email, ['objectClass','totpMruToken'], conn)
	if user is None:
		return ("That's not a user (%s)." % email, 400)
	
	if 'totpUser' not in user['objectClass']:
		return ("User (%s) not configured for TOTP" % email, 400)

	attrs = {
		"totpMruToken": token
	}			
	conn.add_or_modify(user['dn'], user, attrs.keys(), None, attrs)
	return "OK"

def delete_totp_credential(email, env):
	conn = open_database(env)
	user = find_mail_user(env, email, ['objectClass','totpSecret','totpMruToken'], conn)
	if user is None:
		return ("That's not a user (%s)." % email, 400)
	
	if 'totpUser' not in user['objectClass']:
		return "OK"

	attrs = {
		"totpMruToken": None,
		"totpSecret": None,
		"objectClass": user["objectClass"].copy()
	}
	attrs["objectClass"].remove("totpUser")	
	conn.add_or_modify(user['dn'], user, attrs.keys(), None, attrs)
	return "OK"

def kick(env, mail_result=None):
	results = []

	# Include the current operation's result in output.

	if mail_result is not None:
		results.append(mail_result + "\n")

	# Ensure every required alias exists.

	existing_users = get_mail_users(env, as_map=True)
	existing_aliases = get_mail_aliases(env, as_map=True)
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
		add_mail_alias(address, "Required alias", administrator, "", env, do_kick=False)
		if administrator not in existing_aliases: return # don't report the alias in output if the administrator alias isn't in yet -- this is a hack to supress confusing output on initial setup
		results.append("added alias %s (=> %s)\n" % (address, administrator))

	for address in required_aliases:
		ensure_admin_alias_exists(address)

	# Remove auto-generated postmaster/admin on domains we no
	# longer have any other email addresses for.
	for address in existing_aliases:
		user, domain = address.split("@")
		forwards_to = ",".join(existing_aliases[address]["forward_tos"])
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
	if len(pw) < 8:
		raise ValueError("Passwords must be at least eight characters.")

def validate_totp_secret(secret):
	if type(secret) != str or secret.strip() == "":
		raise ValueError("No secret provided.")
	if len(secret) != 32:
		raise ValueError("Secret should be a 32 characters base32 string")

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
