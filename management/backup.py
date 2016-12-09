#!/usr/bin/python3

# This script performs a backup of all user data:
# 1) System services are stopped.
# 2) STORAGE_ROOT/backup/before-backup is executed if it exists.
# 3) An incremental encrypted backup is made using duplicity.
# 4) The stopped services are restarted.
# 5) STORAGE_ROOT/backup/after-backup is executed if it exists.

import os, os.path, shutil, glob, re, datetime, sys
import dateutil.parser, dateutil.relativedelta, dateutil.tz
import rtyaml

from utils import exclusive_process, load_environment, shell, wait_for_service, fix_boto

rsync_ssh_options = [
	"--ssh-options='-i /root/.ssh/id_rsa_miab'",
	"--rsync-options=-e \"/usr/bin/ssh -oStrictHostKeyChecking=no -oBatchMode=yes -p 22 -i /root/.ssh/id_rsa_miab\"",
]

def backup_status(env):
	# Root folder
	backup_root = os.path.join(env["STORAGE_ROOT"], 'backup')

	# What is the current status of backups?
	# Query duplicity to get a list of all backups.
	# Use the number of volumes to estimate the size.
	config = get_backup_config(env)
	now = datetime.datetime.now(dateutil.tz.tzlocal())

	# Are backups dissbled?
	if config["target"] == "off":
		return { }

	backups = { }
	backup_cache_dir = os.path.join(backup_root, 'cache')

	def reldate(date, ref, clip):
		if ref < date: return clip
		rd = dateutil.relativedelta.relativedelta(ref, date)
		if rd.months > 1: return "%d months, %d days" % (rd.months, rd.days)
		if rd.months == 1: return "%d month, %d days" % (rd.months, rd.days)
		if rd.days >= 7: return "%d days" % rd.days
		if rd.days > 1: return "%d days, %d hours" % (rd.days, rd.hours)
		if rd.days == 1: return "%d day, %d hours" % (rd.days, rd.hours)
		return "%d hours, %d minutes" % (rd.hours, rd.minutes)

	# Get duplicity collection status and parse for a list of backups.
	def parse_line(line):
		keys = line.strip().split()
		date = dateutil.parser.parse(keys[1]).astimezone(dateutil.tz.tzlocal())
		return {
			"date": keys[1],
			"date_str": date.strftime("%x %X") + " " + now.tzname(),
			"date_delta": reldate(date, now, "the future?"),
			"full": keys[0] == "full",
			"size": 0, # collection-status doesn't give us the size
			"volumes": keys[2], # number of archive volumes for this backup (not really helpful)
		}

	code, collection_status = shell('check_output', [
		"/usr/bin/duplicity",
		"collection-status",
		"--archive-dir", backup_cache_dir,
		"--gpg-options", "--cipher-algo=AES256",
		"--log-fd", "1",
		config["target"],
		] + rsync_ssh_options,
		get_env(env),
		trap=True)
	if code != 0:
		# Command failed. This is likely due to an improperly configured remote
		# destination for the backups or the last backup job terminated unexpectedly.
		raise Exception("Something is wrong with the backup: " + collection_status)
	for line in collection_status.split('\n'):
		if line.startswith(" full") or line.startswith(" inc"):
			backup = parse_line(line)
			backups[backup["date"]] = backup

	# Look at the target to get the sizes of each of the backups. There is more than one file per backup.
	for fn, size in list_target_files(config):
		m = re.match(r"duplicity-(full|full-signatures|(inc|new-signatures)\.(?P<incbase>\d+T\d+Z)\.to)\.(?P<date>\d+T\d+Z)\.", fn)
		if not m: continue # not a part of a current backup chain
		key = m.group("date")
		backups[key]["size"] += size

	# Ensure the rows are sorted reverse chronologically.
	# This is relied on by should_force_full() and the next step.
	backups = sorted(backups.values(), key = lambda b : b["date"], reverse=True)

	# Get the average size of incremental backups, the size of the
	# most recent full backup, and the date of the most recent
	# backup and the most recent full backup.
	incremental_count = 0
	incremental_size = 0
	first_date = None
	first_full_size = None
	first_full_date = None
	for bak in backups:
		if first_date is None:
			first_date = dateutil.parser.parse(bak["date"])
		if bak["full"]:
			first_full_size = bak["size"]
			first_full_date = dateutil.parser.parse(bak["date"])
			break
		incremental_count += 1
		incremental_size += bak["size"]

	# When will the most recent backup be deleted? It won't be deleted if the next
	# backup is incremental, because the increments rely on all past increments.
	# So first guess how many more incremental backups will occur until the next
	# full backup. That full backup frees up this one to be deleted. But, the backup
	# must also be at least min_age_in_days old too.
	deleted_in = None
	if incremental_count > 0 and first_full_size is not None:
		# How many days until the next incremental backup? First, the part of
		# the algorithm based on increment sizes:
		est_days_to_next_full = (.5 * first_full_size - incremental_size) / (incremental_size/incremental_count)
		est_time_of_next_full = first_date + datetime.timedelta(days=est_days_to_next_full)

		# ...And then the part of the algorithm based on full backup age:
		est_time_of_next_full = min(est_time_of_next_full, first_full_date + datetime.timedelta(days=config["min_age_in_days"]*10+1))

		# It still can't be deleted until it's old enough.
		est_deleted_on = max(est_time_of_next_full, first_date + datetime.timedelta(days=config["min_age_in_days"]))

		deleted_in = "approx. %d days" % round((est_deleted_on-now).total_seconds()/60/60/24 + .5)

	# When will a backup be deleted? Set the deleted_in field of each backup.
	saw_full = False
	for bak in backups:
		if deleted_in:
			# The most recent increment in a chain and all of the previous backups
			# it relies on are deleted at the same time.
			bak["deleted_in"] = deleted_in
		if bak["full"]:
			# Reset when we get to a full backup. A new chain start *next*.
			saw_full = True
			deleted_in = None
		elif saw_full and not deleted_in:
			# We're now on backups prior to the most recent full backup. These are
			# free to be deleted as soon as they are min_age_in_days old.
			deleted_in = reldate(now, dateutil.parser.parse(bak["date"]) + datetime.timedelta(days=config["min_age_in_days"]), "on next daily backup")
			bak["deleted_in"] = deleted_in

	return {
		"backups": backups,
	}

def should_force_full(config, env):
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
			# Return if we should to a full backup, which is based
			# on the size of the increments relative to the full
			# backup, as well as the age of the full backup.
			if inc_size > .5*bak["size"]:
				return True
			if dateutil.parser.parse(bak["date"]) + datetime.timedelta(days=config["min_age_in_days"]*10+1) < datetime.datetime.now(dateutil.tz.tzlocal()):
				return True
			return False
	else:
		# If we got here there are no (full) backups, so make one.
		# (I love for/else blocks. Here it's just to show off.)
		return True

def get_passphrase(env):
	# Get the encryption passphrase. secret_key.txt is 2048 random
	# bits base64-encoded and with line breaks every 65 characters.
	# gpg will only take the first line of text, so sanity check that
	# that line is long enough to be a reasonable passphrase. It
	# only needs to be 43 base64-characters to match AES256's key
	# length of 32 bytes.
	backup_root = os.path.join(env["STORAGE_ROOT"], 'backup')
	with open(os.path.join(backup_root, 'secret_key.txt')) as f:
		passphrase = f.readline().strip()
	if len(passphrase) < 43: raise Exception("secret_key.txt's first line is too short!")

	return passphrase

def get_env(env):
	config = get_backup_config(env)

	env = { "PASSPHRASE" : get_passphrase(env) }

	if get_target_type(config) == 's3':
		env["AWS_ACCESS_KEY_ID"] = config["target_user"]
		env["AWS_SECRET_ACCESS_KEY"] = config["target_pass"]

	return env

def get_target_type(config):
	protocol = config["target"].split(":")[0]
	return protocol

def perform_backup(full_backup):
	env = load_environment()

	exclusive_process("backup")
	config = get_backup_config(env)
	backup_root = os.path.join(env["STORAGE_ROOT"], 'backup')
	backup_cache_dir = os.path.join(backup_root, 'cache')
	backup_dir = os.path.join(backup_root, 'encrypted')

	# Are backups disabled?
	if config["target"] == "off":
		return

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
		# Move the old unencrypted files to a new location outside of
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
	try:
		full_backup = full_backup or should_force_full(config, env)
	except Exception as e:
		# This was the first call to duplicity, and there might
		# be an error already.
		print(e)
		sys.exit(1)

	# Stop services.
	def service_command(service, command, quit=None):
		# Execute silently, but if there is an error then display the output & exit.
		code, ret = shell('check_output', ["/usr/sbin/service", service, command], capture_stderr=True, trap=True)
		if code != 0:
			print(ret)
			if quit:
				sys.exit(code)

	service_command("php5-fpm", "stop", quit=True)
	service_command("postfix", "stop", quit=True)
	service_command("dovecot", "stop", quit=True)

	# Execute a pre-backup script that copies files outside the homedir.
	# Run as the STORAGE_USER user, not as root. Pass our settings in
	# environment variables so the script has access to STORAGE_ROOT.
	pre_script = os.path.join(backup_root, 'before-backup')
	if os.path.exists(pre_script):
		shell('check_call',
			['su', env['STORAGE_USER'], '-c', pre_script, config["target"]],
			env=env)

	# Run a backup of STORAGE_ROOT (but excluding the backups themselves!).
	# --allow-source-mismatch is needed in case the box's hostname is changed
	# after the first backup. See #396.
	try:
		shell('check_call', [
			"/usr/bin/duplicity",
			"full" if full_backup else "incr",
			"--verbosity", "warning", "--no-print-statistics",
			"--archive-dir", backup_cache_dir,
			"--exclude", backup_root,
			"--volsize", "250",
			"--gpg-options", "--cipher-algo=AES256",
			env["STORAGE_ROOT"],
			config["target"],
			"--allow-source-mismatch"
			] + rsync_ssh_options,
			get_env(env))
	finally:
		# Start services again.
		service_command("dovecot", "start", quit=False)
		service_command("postfix", "start", quit=False)
		service_command("php5-fpm", "start", quit=False)

	# Once the migrated backup is included in a new backup, it can be deleted.
	if os.path.isdir(migrated_unencrypted_backup_dir):
		shutil.rmtree(migrated_unencrypted_backup_dir)

	# Remove old backups. This deletes all backup data no longer needed
	# from more than 3 days ago.
	shell('check_call', [
		"/usr/bin/duplicity",
		"remove-older-than",
		"%dD" % config["min_age_in_days"],
		"--verbosity", "error",
		"--archive-dir", backup_cache_dir,
		"--force",
		config["target"]
		] + rsync_ssh_options,
		get_env(env))

	# From duplicity's manual:
	# "This should only be necessary after a duplicity session fails or is
	# aborted prematurely."
	# That may be unlikely here but we may as well ensure we tidy up if
	# that does happen - it might just have been a poorly timed reboot.
	shell('check_call', [
		"/usr/bin/duplicity",
		"cleanup",
		"--verbosity", "error",
		"--archive-dir", backup_cache_dir,
		"--force",
		config["target"]
		] + rsync_ssh_options,
		get_env(env))

	# Change ownership of backups to the user-data user, so that the after-bcakup
	# script can access them.
	if get_target_type(config) == 'file':
		shell('check_call', ["/bin/chown", "-R", env["STORAGE_USER"], backup_dir])

	# Execute a post-backup script that does the copying to a remote server.
	# Run as the STORAGE_USER user, not as root. Pass our settings in
	# environment variables so the script has access to STORAGE_ROOT.
	post_script = os.path.join(backup_root, 'after-backup')
	if os.path.exists(post_script):
		shell('check_call',
			['su', env['STORAGE_USER'], '-c', post_script, config["target"]],
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
	config = get_backup_config(env)
	backup_cache_dir = os.path.join(backup_root, 'cache')

	shell('check_call', [
		"/usr/bin/duplicity",
		"--verbosity", "info",
		"verify",
		"--compare-data",
		"--archive-dir", backup_cache_dir,
		"--exclude", backup_root,
		config["target"],
		env["STORAGE_ROOT"],
	] + rsync_ssh_options, get_env(env))

def run_duplicity_restore(args):
	env = load_environment()
	config = get_backup_config(env)
	backup_cache_dir = os.path.join(env["STORAGE_ROOT"], 'backup', 'cache')
	shell('check_call', [
		"/usr/bin/duplicity",
		"restore",
		"--archive-dir", backup_cache_dir,
		config["target"],
		] + rsync_ssh_options + args,
	get_env(env))

def list_target_files(config):
	import urllib.parse
	try:
		p = urllib.parse.urlparse(config["target"])
	except ValueError:
		return "invalid target"

	if p.scheme == "file":
		return [(fn, os.path.getsize(os.path.join(p.path, fn))) for fn in os.listdir(p.path)]

	elif p.scheme == "rsync":
		rsync_fn_size_re = re.compile(r'.*    ([^ ]*) [^ ]* [^ ]* (.*)')
		rsync_target = '{host}:{path}'

		## _, target_host, target_path = config['target'].split('//')
		target_host = p.netloc
		target_path = p.path
		if not target_path.startswith('/'):
			target_path = '/' + target_path
		if not target_path.endswith('/'):
			target_path += '/'

		rsync_command = [ 'rsync',
					'-e',
					'/usr/bin/ssh -i /root/.ssh/id_rsa_miab -oStrictHostKeyChecking=no -oBatchMode=yes',
					'--list-only',
					'-r',
					rsync_target.format(
						host=target_host,
						path=target_path)
				]

		code, listing = shell('check_output', rsync_command, trap=True)
		if code == 0:
			ret = []
			for l in listing.split('\n'):
				match = rsync_fn_size_re.match(l)
				if match:
					ret.append( (match.groups()[1], int(match.groups()[0].replace(',',''))) )
			return ret
		else:
			raise ValueError("Connection to rsync host failed")

	elif p.scheme == "s3":
		# match to a Region
		fix_boto() # must call prior to importing boto
		import boto.s3
		from boto.exception import BotoServerError
		for region in boto.s3.regions():
			if region.endpoint == p.hostname:
				break
		else:
			raise ValueError("Invalid S3 region/host.")

		bucket = p.path[1:].split('/')[0]
		path = '/'.join(p.path[1:].split('/')[1:]) + '/'

		# If no prefix is specified, set the path to '', otherwise boto won't list the files
		if path == '/':
			path = ''

		if bucket == "":
			raise ValueError("Enter an S3 bucket name.")

		# connect to the region & bucket
		try:
			conn = region.connect(aws_access_key_id=config["target_user"], aws_secret_access_key=config["target_pass"])
			bucket = conn.get_bucket(bucket)
		except BotoServerError as e:
			if e.status == 403:
				raise ValueError("Invalid S3 access key or secret access key.")
			elif e.status == 404:
				raise ValueError("Invalid S3 bucket name.")
			elif e.status == 301:
				raise ValueError("Incorrect region for this bucket.")
			raise ValueError(e.reason)

		return [(key.name[len(path):], key.size) for key in bucket.list(prefix=path)]

	else:
		raise ValueError(config["target"])


def backup_set_custom(env, target, target_user, target_pass, min_age):
	config = get_backup_config(env, for_save=True)

	# min_age must be an int
	if isinstance(min_age, str):
		min_age = int(min_age)

	config["target"] = target
	config["target_user"] = target_user
	config["target_pass"] = target_pass
	config["min_age_in_days"] = min_age

	# Validate.
	try:
		if config["target"] not in ("off", "local"):
			# these aren't supported by the following function, which expects a full url in the target key,
			# which is what is there except when loading the config prior to saving
			list_target_files(config)
	except ValueError as e:
		return str(e)

	write_backup_config(env, config)

	return "OK"

def get_backup_config(env, for_save=False, for_ui=False):
	backup_root = os.path.join(env["STORAGE_ROOT"], 'backup')

	# Defaults.
	config = {
		"min_age_in_days": 3,
		"target": "local",
	}

	# Merge in anything written to custom.yaml.
	try:
		custom_config = rtyaml.load(open(os.path.join(backup_root, 'custom.yaml')))
		if not isinstance(custom_config, dict): raise ValueError() # caught below
		config.update(custom_config)
	except:
		pass

	# When updating config.yaml, don't do any further processing on what we find.
	if for_save:
		return config

	# When passing this back to the admin to show the current settings, do not include
	# authentication details. The user will have to re-enter it.
	if for_ui:
		for field in ("target_user", "target_pass"):
			if field in config:
				del config[field]

	# helper fields for the admin
	config["file_target_directory"] = os.path.join(backup_root, 'encrypted')
	config["enc_pw_file"] = os.path.join(backup_root, 'secret_key.txt')
	if config["target"] == "local":
		# Expand to the full URL.
		config["target"] = "file://" + config["file_target_directory"]
	ssh_pub_key = os.path.join('/root', '.ssh', 'id_rsa_miab.pub')
	if os.path.exists(ssh_pub_key):
		config["ssh_pub_key"] = open(ssh_pub_key, 'r').read()

	return config

def write_backup_config(env, newconfig):
	backup_root = os.path.join(env["STORAGE_ROOT"], 'backup')
	with open(os.path.join(backup_root, 'custom.yaml'), "w") as f:
		f.write(rtyaml.dump(newconfig))

if __name__ == "__main__":
	import sys
	if sys.argv[-1] == "--verify":
		# Run duplicity's verification command to check a) the backup files
		# are readable, and b) report if they are up to date.
		run_duplicity_verification()

	elif sys.argv[-1] == "--status":
		# Show backup status.
		ret = backup_status(load_environment())
		print(rtyaml.dump(ret["backups"]))

	elif len(sys.argv) >= 2 and sys.argv[1] == "--restore":
		# Run duplicity restore. Rest of command line passed as arguments
		# to duplicity. The restore path should be specified.
		run_duplicity_restore(sys.argv[2:])

	else:
		# Perform a backup. Add --full to force a full backup rather than
		# possibly performing an incremental backup.
		full_backup = "--full" in sys.argv
		perform_backup(full_backup)
