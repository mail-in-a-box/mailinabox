#!/usr/bin/python3

# This script performs a backup of all user data:
# 1) System services are stopped while a copy of user data is made.
# 2) An incremental encrypted backup is made using duplicity into the
#    directory STORAGE_ROOT/backup/encrypted. The password used for
#    encryption is stored in backup/secret_key.txt.
# 3) The stopped services are restarted.
# 5) STORAGE_ROOT/backup/after-backup is executd if it exists.

import os, os.path, shutil, glob, re, datetime
import dateutil.parser, dateutil.relativedelta, dateutil.tz

from utils import exclusive_process, load_environment, shell, wait_for_service

# Destroy backups when the most recent increment in the chain
# that depends on it is this many days old.
keep_backups_for_days = 3

def backup_status(env):
	# What is the current status of backups?
	# Loop through all of the files in STORAGE_ROOT/backup/encrypted to
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
	backup_root = os.path.join(env["STORAGE_ROOT"], 'backup')
	backup_dir = os.path.join(backup_root, 'encrypted')
	os.makedirs(backup_dir, exist_ok=True) # os.listdir fails if directory does not exist
	for fn in os.listdir(backup_dir):
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
			}

		backups[key]["size"] += os.path.getsize(os.path.join(backup_dir, fn))

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
		"directory": backup_dir,
		"encpwfile": os.path.join(backup_root, 'secret_key.txt'),
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

	backup_root = os.path.join(env["STORAGE_ROOT"], 'backup')
	backup_cache_dir = os.path.join(backup_root, 'cache')
	backup_dir = os.path.join(backup_root, 'encrypted')

	# In an older version of this script, duplicity was called
	# such that it did not encrypt the backups it created (in
	# backup/duplicity), and instead openssl was called separately
	# after each backup run, creating AES256 encrypted copies of
	# each file created by duplicity in backup/encrypted.
	#
	# We detect the transition by the presence of backup/duplicity
	# and handle it by 'dupliception': we move all the old *un*encrypted
	# duplicity files up out of the backup/duplicity directory (as
	# backup/ is excluded from duplicity runs) in order that it is
	# included in the next run, and we delete backup/encrypted (which
	# duplicity will output files directly to, post-transition).
	old_backup_dir = os.path.join(backup_root, 'duplicity')
	migrated_unencrypted_backup_dir = os.path.join(env["STORAGE_ROOT"], "migrated_unencrypted_backup")
	if os.path.isdir(old_backup_dir):
		# Move the old unencrpyted files to a new location outside of
		# the backup root so they get included in the next (new) backup.
		# Then we'll delete them. Also so that they do not get in the
		# way of duplicity doing a full backup on the first run after
		# we take care of this.
		shutil.move(old_backup_dir, migrated_unencrypted_backup_dir)

		# The backup_dir (backup/encrypted) now has a new purpose.
		# Clear it out.
		shutil.rmtree(backup_dir)

	# On the first run, always do a full backup. Incremental
	# will fail. Otherwise do a full backup when the size of
	# the increments since the most recent full backup are
	# large.
	full_backup = full_backup or should_force_full(env)

	# Stop services.
	shell('check_call', ["/usr/sbin/service", "dovecot", "stop"])
	shell('check_call', ["/usr/sbin/service", "postfix", "stop"])

	# Get the encryption passphrase. secret_key.txt is 2048 random
	# bits base64-encoded and with line breaks every 65 characters.
	# gpg will only take the first line of text, so sanity check that
	# that line is long enough to be a reasonable passphrase. It
	# only needs to be 43 base64-characters to match AES256's key
	# length of 32 bytes.
	with open(os.path.join(backup_root, 'secret_key.txt')) as f:
		passphrase = f.readline().strip()
	if len(passphrase) < 43: raise Exception("secret_key.txt's first line is too short!")
	env_with_passphrase = { "PASSPHRASE" : passphrase }

	# Update the backup mirror directory which mirrors the current
	# STORAGE_ROOT (but excluding the backups themselves!).
	try:
		shell('check_call', [
			"/usr/bin/duplicity",
			"full" if full_backup else "incr",
			"--archive-dir", backup_cache_dir,
			"--exclude", backup_root,
			"--volsize", "250",
			"--gpg-options", "--cipher-algo=AES256",
			env["STORAGE_ROOT"],
			"file://" + backup_dir,
                        "--allow-source-mismatch"
			],
			env_with_passphrase)
	finally:
		# Start services again.
		shell('check_call', ["/usr/sbin/service", "dovecot", "start"])
		shell('check_call', ["/usr/sbin/service", "postfix", "start"])

	# Once the migrated backup is included in a new backup, it can be deleted.
	if os.path.isdir(migrated_unencrypted_backup_dir):
		shutil.rmtree(migrated_unencrypted_backup_dir)

	# Remove old backups. This deletes all backup data no longer needed
	# from more than 3 days ago.
	shell('check_call', [
		"/usr/bin/duplicity",
		"remove-older-than",
		"%dD" % keep_backups_for_days,
		"--archive-dir", backup_cache_dir,
		"--force",
		"file://" + backup_dir
		],
		env_with_passphrase)

	# From duplicity's manual:
	# "This should only be necessary after a duplicity session fails or is
	# aborted prematurely."
	# That may be unlikely here but we may as well ensure we tidy up if
	# that does happen - it might just have been a poorly timed reboot.
	shell('check_call', [
		"/usr/bin/duplicity",
		"cleanup",
		"--archive-dir", backup_cache_dir,
		"--force",
		"file://" + backup_dir
		],
		env_with_passphrase)

	# Change ownership of backups to the user-data user, so that the after-bcakup
	# script can access them.
	shell('check_call', ["/bin/chown", "-R", env["STORAGE_USER"], backup_dir])

	# Execute a post-backup script that does the copying to a remote server.
	# Run as the STORAGE_USER user, not as root. Pass our settings in
	# environment variables so the script has access to STORAGE_ROOT.
	post_script = os.path.join(backup_root, 'after-backup')
	if os.path.exists(post_script):
		shell('check_call',
			['su', env['STORAGE_USER'], '-c', post_script],
			env=env)

	# Our nightly cron job executes system status checks immediately after this
	# backup. Since it checks that dovecot and postfix are running, block for a
	# bit (maximum of 10 seconds each) to give each a chance to finish restarting
	# before the status checks might catch them down. See #381.
	wait_for_service(25, True, env, 10)
	wait_for_service(993, True, env, 10)

def run_duplicity_verification():
	env = load_environment()
	backup_root = os.path.join(env["STORAGE_ROOT"], 'backup')
	backup_cache_dir = os.path.join(backup_root, 'cache')
	backup_dir = os.path.join(backup_root, 'encrypted')
	env_with_passphrase = { "PASSPHRASE" : open(os.path.join(backup_root, 'secret_key.txt')).read() }
	shell('check_call', [
		"/usr/bin/duplicity",
		"--verbosity", "info",
		"verify",
		"--compare-data",
		"--archive-dir", backup_cache_dir,
		"--exclude", backup_root,
		"file://" + backup_dir,
		env["STORAGE_ROOT"],
	], env_with_passphrase)

if __name__ == "__main__":
	import sys
	if sys.argv[-1] == "--verify":
		# Run duplicity's verification command to check a) the backup files
		# are readable, and b) report if they are up to date.
		run_duplicity_verification()
	else:
		# Perform a backup. Add --full to force a full backup rather than
		# possibly performing an incremental backup.
		full_backup = "--full" in sys.argv
		perform_backup(full_backup)
