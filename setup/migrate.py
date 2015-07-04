#!/usr/bin/python3

# Migrates any file structures, database schemas, etc. between versions of Mail-in-a-Box.

# We have to be careful here that any dependencies are already installed in the previous
# version since this script runs before all other aspects of the setup script.

import sys, os, os.path, glob, re, shutil

sys.path.insert(0, 'management')
from utils import load_environment, save_environment, shell

def migration_1(env):
	# Re-arrange where we store SSL certificates. There was a typo also.

	def move_file(fn, domain_name_escaped, filename):
		# Moves an SSL-related file into the right place.
		fn1 = os.path.join( env["STORAGE_ROOT"], 'ssl', domain_name_escaped, file_type)
		os.makedirs(os.path.dirname(fn1), exist_ok=True)
		shutil.move(fn, fn1)

	# Migrate the 'domains' directory.
	for sslfn in glob.glob(os.path.join( env["STORAGE_ROOT"], 'ssl/domains/*' )):
		fn = os.path.basename(sslfn)
		m = re.match("(.*)_(certifiate.pem|cert_sign_req.csr|private_key.pem)$", fn)
		if m:
			# get the new name for the file
			domain_name, file_type = m.groups()
			if file_type == "certifiate.pem": file_type = "ssl_certificate.pem" # typo
			if file_type == "cert_sign_req.csr": file_type = "certificate_signing_request.csr" # nicer
			move_file(sslfn, domain_name, file_type)

	# Move the old domains directory if it is now empty.
	try:
		os.rmdir(os.path.join( env["STORAGE_ROOT"], 'ssl/domains'))
	except:
		pass

def migration_2(env):
	# Delete the .dovecot_sieve script everywhere. This was formerly a copy of our spam -> Spam
	# script. We now install it as a global script, and we use managesieve, so the old file is
	# irrelevant. Also delete the compiled binary form.
	for fn in glob.glob(os.path.join(env["STORAGE_ROOT"], 'mail/mailboxes/*/*/.dovecot.sieve')):
		os.unlink(fn)
	for fn in glob.glob(os.path.join(env["STORAGE_ROOT"], 'mail/mailboxes/*/*/.dovecot.svbin')):
		os.unlink(fn)

def migration_3(env):
	# Move the migration ID from /etc/mailinabox.conf to $STORAGE_ROOT/mailinabox.version
	# so that the ID stays with the data files that it describes the format of. The writing
	# of the file will be handled by the main function.
	pass

def migration_4(env):
	# Add a new column to the mail users table where we can store administrative privileges.
	db = os.path.join(env["STORAGE_ROOT"], 'mail/users.sqlite')
	shell("check_call", ["sqlite3", db, "ALTER TABLE users ADD privileges TEXT NOT NULL DEFAULT ''"])

def migration_5(env):
	# The secret key for encrypting backups was world readable. Fix here.
	os.chmod(os.path.join(env["STORAGE_ROOT"], 'backup/secret_key.txt'), 0o600)

def migration_6(env):
	# We now will generate multiple DNSSEC keys for different algorithms, since TLDs may
	# not support them all. .email only supports RSA/SHA-256. Rename the keys.conf file
	# to be algorithm-specific.
	basepath = os.path.join(env["STORAGE_ROOT"], 'dns/dnssec')
	shutil.move(os.path.join(basepath, 'keys.conf'), os.path.join(basepath, 'RSASHA1-NSEC3-SHA1.conf'))

def migration_7(env):
	# I previously wanted domain names to be stored in Unicode in the database. Now I want them
	# to be in IDNA. Affects aliases only.
	import sqlite3
	conn = sqlite3.connect(os.path.join(env["STORAGE_ROOT"], "mail/users.sqlite"))

	# Get existing alias source addresses.
	c = conn.cursor()
	c.execute('SELECT source FROM aliases')
	aliases = [ row[0] for row in c.fetchall() ]

	# Update to IDNA-encoded domains.
	for email in aliases:
		try:
			localpart, domainpart = email.split("@")
			domainpart = domainpart.encode("idna").decode("ascii")
			newemail = localpart + "@" + domainpart
			if newemail != email:
				c = conn.cursor()
				c.execute("UPDATE aliases SET source=? WHERE source=?", (newemail, email))
				if c.rowcount != 1: raise ValueError("Alias not found.")
				print("Updated alias", email, "to", newemail)
		except Exception as e:
			print("Error updating IDNA alias", email, e)

	# Save.
	conn.commit()

def migration_8(env):
	# Delete DKIM keys. We had generated 1024-bit DKIM keys.
	# By deleting the key file we'll automatically generate
	# a new key, which will be 2048 bits.
	os.unlink(os.path.join(env['STORAGE_ROOT'], 'mail/dkim/mail.private'))

def migration_9(env):
	# Switch from storing alias ownership in one column (used for both
	# directions) to two columns (one for determining inbound forward-tos and
	# one for determining outbound permitted-senders). This was motivated by the
	# addition of #427 ("Reject outgoing mail if FROM does not match Login") -
	# which introduced the notion of outbound permitted-senders.
	db = os.path.join(env["STORAGE_ROOT"], 'mail/users.sqlite')
	# Move the old aliases table to one side.
	shell("check_call", ["sqlite3", db, "ALTER TABLE aliases RENAME TO aliases_8"])
	# Create the new aliases table, initially empty.
	shell("check_call", ["sqlite3", db, "CREATE TABLE aliases (id INTEGER PRIMARY KEY AUTOINCREMENT, address TEXT NOT NULL UNIQUE, receivers TEXT NOT NULL, senders TEXT NOT NULL)"])

	import sqlite3
	conn = sqlite3.connect(os.path.join(env["STORAGE_ROOT"], "mail/users.sqlite"))

	c = conn.cursor()
	c.execute('SELECT email FROM users')
	valid_logins = [ row[0] for row in c.fetchall() ]

	c = conn.cursor()
	c.execute('SELECT source, destination FROM aliases_8')
	aliases = { row[0]: row[1] for row in c.fetchall() }

	# Populate the new aliases table. Forward-to addresses (receivers) is taken
	# directly from the old destination column. Permitted-sender logins
	# (senders) is made up of only those addresses in the old destination column
	# that are valid logins, as other values are not relevant. Their presence
	# would not do any harm, except that it would make the aliases UI confusing
	# on upgraded boxes.
	for source in aliases:

		address = source
		receivers = aliases[source]

		validated_senders = []
		for login in aliases[source].split(","):
			login = login.strip()
			if login == "": continue
			if login in valid_logins:
				validated_senders.append(login)

		senders = ",".join(validated_senders)

		c = conn.cursor()
		c.execute("INSERT INTO aliases (address, receivers, senders) VALUES (?, ?, ?)", (address, receivers, senders))

	# Save.
	conn.commit()

	# Delete the old aliases table.
	shell("check_call", ["sqlite3", db, "DROP TABLE aliases_8"])

def get_current_migration():
	ver = 0
	while True:
		next_ver = (ver + 1)
		migration_func = globals().get("migration_%d" % next_ver)
		if not migration_func:
			return ver
		ver = next_ver

def run_migrations():
	if not os.access("/etc/mailinabox.conf", os.W_OK, effective_ids=True):
		print("This script must be run as root.", file=sys.stderr)
		sys.exit(1)

	env = load_environment()

	migration_id_file = os.path.join(env['STORAGE_ROOT'], 'mailinabox.version')
	migration_id = None
	if os.path.exists(migration_id_file):
		with open(migration_id_file) as f:
			migration_id = f.read().strip();

	if migration_id is None:
		# Load the legacy location of the migration ID. We'll drop support
		# for this eventually.
		migration_id = env.get("MIGRATIONID")

	if migration_id is None:
		print()
		print("%s file doesn't exists. Skipping migration..." % (migration_id_file,))
		return

	ourver = int(migration_id)

	while True:
		next_ver = (ourver + 1)
		migration_func = globals().get("migration_%d" % next_ver)

		if not migration_func:
			# No more migrations to run.
			break

		print()
		print("Running migration to Mail-in-a-Box #%d..." % next_ver)

		try:
			migration_func(env)
		except Exception as e:
			print()
			print("Error running the migration script:")
			print()
			print(e)
			print()
			print("Your system may be in an inconsistent state now. We're terribly sorry. A re-install from a backup might be the best way to continue.")
			sys.exit(1)

		ourver = next_ver

		# Write out our current version now. Do this sooner rather than later
		# in case of any problems.
		with open(migration_id_file, "w") as f:
			f.write(str(ourver) + "\n")

		# Delete the legacy location of this field.
		if "MIGRATIONID" in env:
			del env["MIGRATIONID"]
			save_environment(env)

		# iterate and try next version...

if __name__ == "__main__":
	if sys.argv[-1] == "--current":
		# Return the number of the highest migration.
		print(str(get_current_migration()))
	elif sys.argv[-1] == "--migrate":
		# Perform migrations.
		run_migrations()

