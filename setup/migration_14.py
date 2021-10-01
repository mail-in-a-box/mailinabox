#!/usr/bin/python3
# -*- indent-tabs-mode: t; tab-width: 4; python-indent-offset: 4; -*-

#
# helper functions for migration #14 / miabldap-migration #2
#

import sys, os, ldap3, idna
from utils import shell
from mailconfig import (
	add_required_aliases,
	required_alias_names,
	get_mail_domains
)


def utf8_from_idna(domain_idna):
	try:
		return idna.decode(domain_idna.encode("ascii"))
	except (UnicodeError, idna.IDNAError):
		# Failed to decode IDNA, should never happen
		return domain_idna


def apply_schema_changes(env, ldapvars, ldif_change_fn):
	# 1. save LDAP_BASE data to ldif
	slapd_conf = os.path.join(env["STORAGE_ROOT"], "ldap/slapd.d")
	fail_fn = os.path.join(env["STORAGE_ROOT"], "ldap/failed_migration.txt")
	ldif = shell("check_output", [
		"/usr/sbin/slapcat",
		"-F", slapd_conf,
		"-b", ldapvars.LDAP_BASE
	])

	# 2. wipe out existing database configuration and database
	#    2a. set the creation parameters
	ORGANIZATION="Mail-In-A-Box"
	LDAP_DOMAIN="mailinabox"
	shell("check_output", [
		"/usr/bin/debconf-set-selections"
	], input=f'''slapd shared/organization string {ORGANIZATION}
slapd slapd/domain string {LDAP_DOMAIN}
slapd slapd/password1 password {ldapvars.LDAP_ADMIN_PASSWORD}
slapd slapd/password2 password {ldapvars.LDAP_ADMIN_PASSWORD}
'''.encode('utf-8')
	)

	#    2b. recreate ldap config and database
	shell("check_call", [
		"/usr/sbin/dpkg-reconfigure",
		"--frontend=noninteractive",
		"slapd"
	])

	#    2c. clear passwords from debconf
	shell("check_output", [
		"/usr/bin/debconf-set-selections"
	], input='''slapd slapd/password1 password
slapd slapd/password2 password
'''.encode('utf-8')
	)

	# 3. make desired ldif changes
	#   3a. first, remove dc=mailinabox and
	#       cn=admin,dc=mailinabox. they were both created during
	#       dpkg-reconfigure and can't be readded
	entries = ldif.split("\n\n")
	keep = []
	removed = []
	remove = [
		"dn: " + ldapvars.LDAP_BASE,
		"dn: " + ldapvars.LDAP_ADMIN_DN
	]
	for entry in entries:
		dn = entry.split("\n")[0]
		if dn not in remove:
			keep.append(entry)
		else:
			removed.append(entry)
			
	#   3b. call the given ldif change function
	ldif = ldif_change_fn("\n\n".join(keep))
	#ldif = ldif_change_fn(ldif)
	
	# 4. re-create schemas and other config
	shell("check_call", [
		"setup/ldap.sh",
		"-v",
		"-config", "server"
	])

	# 5. restore LDAP_BASE data
	code, ret = shell("check_output", [
		"/usr/sbin/slapadd",
		"-F", slapd_conf,
		"-b", ldapvars.LDAP_BASE,
		"-v",
		"-c"
	], input=ldif.encode('utf-8'), trap=True, capture_stderr=True)
	
	if code != 0:
		try:
			with open(fail_fn, "w") as of:
				of.write("# slapadd -F %s -b %s -v -c\n" %
						 (slapd_conf, ldapvars.LDAP_BASE))
				of.write(ldif)
			print("See saved data in %s" % fail_fn)
		except Exception:
			pass
		
		raise ValueError("Could not restore data: exit code=%s: output=%s" % (code, ret))



def add_utf8_mail_addresses(env, ldap, ldap_users_base):
	# if the mail attribute of users or aliases is idna encoded, also
	# add a utf8 version of the address to the mail attribute so the
	# user or alias will be known by multiple addresses (idna and
	# utf8)
	pager = ldap.paged_search(ldap_users_base, "(|(objectClass=mailGroup)(objectClass=mailUser))", attributes=['mail'])
	changes = []
	for rec in pager:
		mail_idna_lc = []
		for addr in rec['mail']:
			mail_idna_lc = addr.lower()
		
		changed = False
		new_mail = []
		for addr in rec['mail']:
			new_mail.append(addr)
			name = addr.split('@')[0]
			domain = addr.split('@', 1)[1]
			addr_utf8 = name + '@' + utf8_from_idna(domain)
			addr_utf8_lc = addr_utf8.lower()
			if addr_utf8 != addr and addr_utf8_lc not in mail_lc:
				new_mail.append(addr_utf8)
				print("Add '%s' for %s" % (addr_utf8, addr))
				changed = True
		if changed:
			changes.append({"rec":rec, "mail":new_mail})

	for change in changes:
		ldap.modify_record(
			change["rec"],
			{ "mail": change["mail"] }
		)



def add_namedProperties_objectclass(env, ldap, ldap_aliases_base):
	# ensure every alias has a namedProperties objectClass attached
	pager = ldap.paged_search(ldap_aliases_base, "(&(objectClass=mailGroup)(!(objectClass=namedProperties)))", attributes=['objectClass'])
	changes = []
	for rec in pager:
		newoc = rec['objectClass'].copy()
		newoc.append('namedProperties')
		changelist = {
			'objectClass': newoc,
		}
		changes.append({'rec': rec, 'changelist': changelist})

	for change in changes:
		ldap.modify_record(change['rec'], change['changelist'])

		
def add_auto_tag(env, ldap, ldap_aliases_base):
	# add namedProperty=auto to existing required aliases
	# this step is needed to upgrade miabldap systems
	name_q = [
		"(mail=hostmaster@"+env['PRIMARY_HOSTNAME']+")"
	]
	for name in required_alias_names:
		name_q.append("(mail=%s@*)" % name)
		
	q = [
		"(objectClass=mailGroup)",
		"(!(namedProperty=auto))",
		"(|%s)" % "".join(name_q)
	]
	pager = ldap.paged_search(
		ldap_aliases_base,
		"(&%s)" % "".join(q),
		attributes=['namedProperty']
	)
	changes = []
	for rec in pager:
		newval = rec["namedProperty"].copy()
		newval.append("auto")
		changes.append({"rec": rec, "namedProperty": newval})
		
	for change in changes:
		ldap.modify_record(
			change["rec"],
			{"namedProperty": change["namedProperty"]}
		)



def add_mailDomain_objectclass(env, ldap, ldap_domains_base):
	# ensure every domain has a mailDomain objectClass attached
	pager = ldap.paged_search(ldap_domains_base, "(&(objectClass=domain)(!(objectClass=mailDomain)))", attributes=['objectClass', 'dc', 'dcIntl'])
	changes = []
	for rec in pager:
		newoc = rec['objectClass'].copy()
		newoc.append('mailDomain')
		changelist = {
			'objectClass': newoc,
			'dcIntl': [ utf8_from_idna(rec['dc'][0]) ]
		}
		changes.append({'rec': rec, 'changelist': changelist})

	for change in changes:
		ldap.modify_record(change['rec'], change['changelist'])


def ensure_required_aliases(env, ldapvars, ldap):
	# ensure every domain has its required aliases
	env_combined = env.copy()
	env_combined.update(ldapvars)
	errors = []
	for domain_idna in get_mail_domains(ldapvars):
		results = add_required_aliases(env_combined, ldap, domain_idna)
		for result in results:
			if isinstance(result, str):
				print(result)
			else:
				print("Error: %s" % result[0])
				errors.append(result[0])
	if len(errors)>0:
		raise ValueError("Some required aliases could not be added")
	

