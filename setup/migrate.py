#!/usr/bin/python3

# Migrates any file structures, database schemas, etc. between versions of Mail-in-a-Box.

# We have to be careful here that any dependencies are already installed in the previous
# version since this script runs before all other aspects of the setup script.

import sys, os, os.path, glob, re, shutil

sys.path.insert(0, 'management')
from utils import load_environment, save_environment, safe_domain_name

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

	ourver = int(env.get("MIGRATIONID", "0"))

	while True:
		next_ver = (ourver + 1)
		migration_func = globals().get("migration_%d" % next_ver)

		if not migration_func:
			# No more migrations to run.
			break

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
		env["MIGRATIONID"] = ourver
		save_environment(env)

		# iterate and try next version...

if __name__ == "__main__":
	if sys.argv[-1] == "--current":
		# Return the number of the highest migration.
		print(str(get_current_migration()))
	elif sys.argv[-1] == "--migrate":
		# Perform migrations.
		run_migrations()

