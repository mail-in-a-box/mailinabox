#!/usr/bin/python3

# This script performs a backup of all user data:
# 1) System services are stopped while a copy of user data is made.
# 2) An incremental backup is made using duplicity into the
#    directory STORAGE_ROOT/backup/duplicity.
# 3) The stopped services are restarted.
# 4) The backup files are encrypted with a long password (stored in
#    backup/secret_key.txt) to STORAGE_ROOT/backup/encrypted.
# 5) STORAGE_ROOT/backup/after-backup is executd if it exists.

import os, os.path, shutil, glob, re, datetime
import dateutil.parser, dateutil.relativedelta, dateutil.tz

from utils import exclusive_process, load_environment, shell

# destroy backups when the most recent increment in the chain
# that depends on it is this many days old.
keep_backups_for_days = 3

def backup_status(env):
	# What is the current status of backups?
	# Loop through all of the files in STORAGE_ROOT/backup/duplicity to
	# get a list of all of the backups taken and sum up file sizes to
	# see how large the storage is.

	now = datetime.datetime.now(dateutil.tz.tzlocal())
	def reldate(date, ref, clip):
		if ref < date: return clip
		rd = dateutil.relativedelta.relativedelta(ref, date)
		if rd.months > 1: return "%d months, %d days" % (rd.months, rd.days)
		if rd.months == 1: return "%d month, %d days" % (rd.months, rd.days)
		if rd.days >= 7: return "%d days" % rd.days
		if rd.days > 1: return "%d days, %d hours" % (rd.days, rd.hours)
		if rd.days == 1: return "%d day, %d hours" % (rd.days, rd.hours)
		return "%d hours, %d minutes" % (rd.hours, rd.minutes)

	backups = { }
	basedir = os.path.join(env['STORAGE_ROOT'], 'backup/duplicity/')
	encdir = os.path.join(env['STORAGE_ROOT'], 'backup/encrypted/')
	os.makedirs(basedir, exist_ok=True) # os.listdir fails if directory does not exist
	for fn in os.listdir(basedir):
		m = re.match(r"duplicity-(full|full-signatures|(inc|new-signatures)\.(?P<incbase>\d+T\d+Z)\.to)\.(?P<date>\d+T\d+Z)\.", fn)
		if not m: raise ValueError(fn)

		key = m.group("date")
		if key not in backups:
			date = dateutil.parser.parse(m.group("date"))
			backups[key] = {
				"date": m.group("date"),
				"date_str": date.strftime("%x %X"),
				"date_delta": reldate(date, now, "the future?"),
				"full": m.group("incbase") is None,
				"previous": m.group("incbase"),
				"size": 0,
				"encsize": 0,
			}

		backups[key]["size"] += os.path.getsize(os.path.join(basedir, fn))

		# Also check encrypted size.
		encfn = os.path.join(encdir, fn + ".enc")
		if os.path.exists(encfn):
			backups[key]["encsize"] += os.path.getsize(encfn)

	# Ensure the rows are sorted reverse chronologically.
	# This is relied on by should_force_full() and the next step.
	backups = sorted(backups.values(), key = lambda b : b["date"], reverse=True)

	# Get the average size of incremental backups and the size of the
	# most recent full backup.
	incremental_count = 0
	incremental_size = 0
	first_full_size = None
	for bak in backups:
		if bak["full"]:
			first_full_size = bak["size"]
			break
		incremental_count += 1
		incremental_size += bak["size"]
	
	# Predict how many more increments until the next full backup,
	# and add to that the time we hold onto backups, to predict
	# how long the most recent full backup+increments will be held
	# onto. Round up since the backup occurs on the night following
	# when the threshold is met.
	deleted_in = None
	if incremental_count > 0 and first_full_size is not None:
		deleted_in = "approx. %d days" % round(keep_backups_for_days + (.5 * first_full_size - incremental_size) / (incremental_size/incremental_count) + .5)

	# When will a backup be deleted?
	saw_full = False
	days_ago = now - datetime.timedelta(days=keep_backups_for_days)
	for bak in backups:
		if deleted_in:
			# Subsequent backups are deleted when the most recent increment
			# in the chain would be deleted.
			bak["deleted_in"] = deleted_in
		if bak["full"]:
			# Reset when we get to a full backup. A new chain start next.
			saw_full = True
			deleted_in = None
		elif saw_full and not deleted_in:
			# Mark deleted_in only on the first increment after a full backup.
			deleted_in = reldate(days_ago, dateutil.parser.parse(bak["date"]), "on next daily backup")
			bak["deleted_in"] = deleted_in

	return {
		"directory": basedir,
		"encpwfile": os.path.join(env['STORAGE_ROOT'], 'backup/secret_key.txt'),
		"encdirectory": encdir,
		"tz": now.tzname(),
		"backups": backups,
	}

def should_force_full(env):
	# Force a full backup when the total size of the increments
	# since the last full backup is greater than half the size
	# of that full backup.
	inc_size = 0
	for bak in backup_status(env)["backups"]:
		if not bak["full"]:
			# Scan through the incremental backups cumulating
			# size...
			inc_size += bak["size"]
		else:
			# ...until we reach the most recent full backup.
			# Return if we should to a full backup.
			return inc_size > .5*bak["size"]
	else:
		# If we got here there are no (full) backups, so make one.
		# (I love for/else blocks. Here it's just to show off.)
		return True

def perform_backup(full_backup):
	env = load_environment()

	exclusive_process("backup")

	# Ensure the backup directory exists.
	backup_dir = os.path.join(env["STORAGE_ROOT"], 'backup')
	backup_duplicity_dir = os.path.join(backup_dir, 'duplicity')
	os.makedirs(backup_duplicity_dir, exist_ok=True)

	# On the first run, always do a full backup. Incremental
	# will fail. Otherwise do a full backup when the size of
	# the increments since the most recent full backup are
	# large.
	full_backup = full_backup or should_force_full(env)

	# Stop services.
	shell('check_call', ["/usr/sbin/service", "dovecot", "stop"])
	shell('check_call', ["/usr/sbin/service", "postfix", "stop"])

	# Update the backup mirror directory which mirrors the current
	# STORAGE_ROOT (but excluding the backups themselves!).
	try:
		shell('check_call', [
			"/usr/bin/duplicity",
			"full" if full_backup else "incr",
			"--no-encryption",
			"--archive-dir", "/tmp/duplicity-archive-dir",
			"--name", "mailinabox",
			"--exclude", backup_dir,
			"--volsize", "100",
			"--verbosity", "warning",
			env["STORAGE_ROOT"],
			"file://" + backup_duplicity_dir
			])
	finally:
		# Start services again.
		shell('check_call', ["/usr/sbin/service", "dovecot", "start"])
		shell('check_call', ["/usr/sbin/service", "postfix", "start"])

	# Remove old backups. This deletes all backup data no longer needed
	# from more than 31 days ago. Must do this before destroying the
	# cache directory or else this command will re-create it.
	shell('check_call', [
		"/usr/bin/duplicity",
		"remove-older-than",
		"%dD" % keep_backups_for_days,
		"--archive-dir", "/tmp/duplicity-archive-dir",
		"--name", "mailinabox",
		"--force",
		"--verbosity", "warning",
		"file://" + backup_duplicity_dir
		])

	# Remove duplicity's cache directory because it's redundant with our backup directory.
	shutil.rmtree("/tmp/duplicity-archive-dir")

	# Encrypt all of the new files.
	backup_encrypted_dir = os.path.join(backup_dir, 'encrypted')
	os.makedirs(backup_encrypted_dir, exist_ok=True)
	for fn in os.listdir(backup_duplicity_dir):
		fn2 = os.path.join(backup_encrypted_dir, fn) + ".enc"
		if os.path.exists(fn2): continue

		# Encrypt the backup using the backup private key.
		shell('check_call', [
			"/usr/bin/openssl",
			"enc",
			"-aes-256-cbc",
			"-a",
			"-salt",
			"-in", os.path.join(backup_duplicity_dir, fn),
			"-out", fn2,
			"-pass", "file:%s" % os.path.join(backup_dir, "secret_key.txt"),
			])

		# The backup can be decrypted with:
		# openssl enc -d -aes-256-cbc -a -in latest.tgz.enc -out /dev/stdout -pass file:secret_key.txt | tar -z

	# Remove encrypted backups that are no longer needed.
	for fn in os.listdir(backup_encrypted_dir):
		fn2 = os.path.join(backup_duplicity_dir, fn.replace(".enc", ""))
		if os.path.exists(fn2): continue
		os.unlink(os.path.join(backup_encrypted_dir, fn))

	# Execute a post-backup script that does the copying to a remote server.
	# Run as the STORAGE_USER user, not as root. Pass our settings in
	# environment variables so the script has access to STORAGE_ROOT.
	post_script = os.path.join(backup_dir, 'after-backup')
	if os.path.exists(post_script):
		shell('check_call',
			['su', env['STORAGE_USER'], '-c', post_script],
			env=env)

if __name__ == "__main__":
	import sys
	full_backup = "--full" in sys.argv
	perform_backup(full_backup)
