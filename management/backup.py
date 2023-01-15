#!/usr/local/lib/mailinabox/env/bin/python

# This script performs a backup of all user data:
# 1) System services are stopped.
# 2) STORAGE_ROOT/backup/before-backup is executed if it exists.
# 3) An incremental encrypted backup is made using duplicity.
# 4) The stopped services are restarted.
# 5) STORAGE_ROOT/backup/after-backup is executed if it exists.

import os, os.path, shutil, glob, re, datetime, sys
import dateutil.parser, dateutil.relativedelta, dateutil.tz
import rtyaml
from exclusiveprocess import Lock

from utils import load_environment, shell, wait_for_service

def get_backup_root_directory(env):
	return os.path.join(env["STORAGE_ROOT"], 'backup')

def get_backup_cache_directory(env):
	return os.path.join(get_backup_root_directory(env), 'cache')

def get_backup_encrypted_directory(env):
	return os.path.join(get_backup_root_directory(env), 'encrypted')

def get_backup_configuration_file(env):
	return os.path.join(get_backup_root_directory(env), 'custom.yaml')

def get_backup_encryption_key_file(env):
	return os.path.join(get_backup_root_directory(env), 'secret_key.txt')

def backup_status(env):
	# If backups are disabled, return no status.
	config = get_backup_config(env)
	if config["type"] == "off":
		return { }

	# Query duplicity to get a list of all full and incremental
	# backups available.

	backups = { }
	now = datetime.datetime.now(dateutil.tz.tzlocal())
	backup_root = get_backup_root_directory(env)
	backup_cache_dir = get_backup_cache_directory(env)

	def reldate(date, ref, clip):
		if ref < date: return clip
		rd = dateutil.relativedelta.relativedelta(ref, date)
		if rd.years > 1: return "%d years, %d months" % (rd.years, rd.months)
		if rd.years == 1: return "%d year, %d months" % (rd.years, rd.months)
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
			"date_str": date.strftime("%Y-%m-%d %X") + " " + now.tzname(),
			"date_delta": reldate(date, now, "the future?"),
			"full": keys[0] == "full",
			"size": 0, # collection-status doesn't give us the size
			"volumes": int(keys[2]), # number of archive volumes for this backup (not really helpful)
		}

	code, collection_status = shell('check_output', [
		"/usr/bin/duplicity",
		"collection-status",
		"--archive-dir", backup_cache_dir,
		"--gpg-options", "--cipher-algo=AES256",
		"--log-fd", "1",
		config["target_url"],
		] + get_duplicity_additional_args(env),
		get_duplicity_env_vars(env),
		trap=True)
	if code != 0:
		# Command failed. This is likely due to an improperly configured remote
		# destination for the backups or the last backup job terminated unexpectedly.
		raise Exception("Something is wrong with the backup: " + collection_status)
	for line in collection_status.split('\n'):
		if line.startswith(" full") or line.startswith(" inc"):
			backup = parse_line(line)
			backups[backup["date"]] = backup

	# Look at the target directly to get the sizes of each of the backups. There is more than one file per backup.
	# Starting with duplicity in Ubuntu 18.04, "signatures" files have dates in their
	# filenames that are a few seconds off the backup date and so don't line up
	# with the list of backups we have. Track unmatched files so we know how much other
	# space is used for those.
	unmatched_file_size = 0
	for fn, size in list_target_files(config):
		m = re.match(r"duplicity-(full|full-signatures|(inc|new-signatures)\.(?P<incbase>\d+T\d+Z)\.to)\.(?P<date>\d+T\d+Z)\.", fn)
		if not m: continue # not a part of a current backup chain
		key = m.group("date")
		if key in backups:
			backups[key]["size"] += size
		else:
			unmatched_file_size += size

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
	if incremental_count > 0 and incremental_size > 0 and first_full_size is not None:
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
		"unmatched_file_size": unmatched_file_size,
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
	with open(get_backup_encryption_key_file(env)) as f:
		passphrase = f.readline().strip()
	if len(passphrase) < 43: raise Exception("secret_key.txt's first line is too short!")

	return passphrase

def get_duplicity_additional_args(env):
	config = get_backup_config(env)

	if config["type"] == 'rsync':
		# Extract a port number for the ssh transport.  Duplicity accepts the
		# optional port number syntax in the target, but it doesn't appear to act
		# on it, so we set the ssh port explicitly via the duplicity options.
		from urllib.parse import urlsplit
		try:
			port = urlsplit(config["target_url"]).port
		except ValueError:
			port = 22

		return [
			f"--ssh-options= -i /root/.ssh/id_rsa_miab -p {port}",
			f"--rsync-options= -e \"/usr/bin/ssh -oStrictHostKeyChecking=no -oBatchMode=yes -p {port} -i /root/.ssh/id_rsa_miab\"",
		]
	elif config["type"] == 's3':
		additional_args = ["--s3-endpoint-url", config["s3_endpoint_url"]]

		if "s3_region_name" in config:
			additional_args.append("--s3-region-name")
			additional_args.append(config["s3_region_name"])

		return additional_args

	return []

def get_duplicity_env_vars(env):
	config = get_backup_config(env)

	env = { "PASSPHRASE" : get_passphrase(env) }

	if config["type"] == 's3':
		env["AWS_ACCESS_KEY_ID"] = config["s3_access_key_id"]
		env["AWS_SECRET_ACCESS_KEY"] = config["s3_secret_access_key"]

	return env

def perform_backup(full_backup):
	env = load_environment()

	# Create an global exclusive lock so that the backup script
	# cannot be run more than one.
	Lock(die=True).forever()

	config = get_backup_config(env)
	backup_root = get_backup_root_directory(env)
	backup_cache_dir = get_backup_cache_directory(env)
	backup_dir = get_backup_encrypted_directory(env)

	# Are backups disabled?
	if config["type"] == "off":
		return

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

	service_command("php8.0-fpm", "stop", quit=True)
	service_command("postfix", "stop", quit=True)
	service_command("dovecot", "stop", quit=True)
	service_command("postgrey", "stop", quit=True)

	# Execute a pre-backup script that copies files outside the homedir.
	# Run as the STORAGE_USER user, not as root. Pass our settings in
	# environment variables so the script has access to STORAGE_ROOT.
	pre_script = os.path.join(backup_root, 'before-backup')
	if os.path.exists(pre_script):
		shell('check_call',
			['su', env['STORAGE_USER'], '-c', pre_script, config["target_url"]],
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
			config["target_url"],
			"--allow-source-mismatch"
			] + get_duplicity_additional_args(env),
			get_duplicity_env_vars(env))
	finally:
		# Start services again.
		service_command("postgrey", "start", quit=False)
		service_command("dovecot", "start", quit=False)
		service_command("postfix", "start", quit=False)
		service_command("php8.0-fpm", "start", quit=False)

	# Remove old backups. This deletes all backup data no longer needed
	# from more than 3 days ago.
	shell('check_call', [
		"/usr/bin/duplicity",
		"remove-older-than",
		"%dD" % config["min_age_in_days"],
		"--verbosity", "error",
		"--archive-dir", backup_cache_dir,
		"--force",
		config["target_url"]
		] + get_duplicity_additional_args(env),
		get_duplicity_env_vars(env))

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
		config["target_url"]
		] + get_duplicity_additional_args(env),
		get_duplicity_env_vars(env))

	# Change ownership of backups to the user-data user, so that the after-bcakup
	# script can access them.
	if config["type"] == 'local':
		shell('check_call', ["/bin/chown", "-R", env["STORAGE_USER"], backup_dir])

	# Execute a post-backup script that does the copying to a remote server.
	# Run as the STORAGE_USER user, not as root. Pass our settings in
	# environment variables so the script has access to STORAGE_ROOT.
	post_script = os.path.join(backup_root, 'after-backup')
	if os.path.exists(post_script):
		shell('check_call',
			['su', env['STORAGE_USER'], '-c', post_script, config["target_url"]],
			env=env)

	# Our nightly cron job executes system status checks immediately after this
	# backup. Since it checks that dovecot and postfix are running, block for a
	# bit (maximum of 10 seconds each) to give each a chance to finish restarting
	# before the status checks might catch them down. See #381.
	wait_for_service(25, True, env, 10)
	wait_for_service(993, True, env, 10)

def run_duplicity_verification():
	env = load_environment()
	backup_root = get_backup_root_directory(env)
	config = get_backup_config(env)
	backup_cache_dir = get_backup_cache_directory(env)

	shell('check_call', [
		"/usr/bin/duplicity",
		"--verbosity", "info",
		"verify",
		"--compare-data",
		"--archive-dir", backup_cache_dir,
		"--exclude", backup_root,
		config["target_url"],
		env["STORAGE_ROOT"],
	] + get_duplicity_additional_args(env), get_duplicity_env_vars(env))

def run_duplicity_restore(args):
	env = load_environment()
	config = get_backup_config(env)
	backup_cache_dir = get_backup_cache_directory(env)
	shell('check_call', [
		"/usr/bin/duplicity",
		"restore",
		"--archive-dir", backup_cache_dir,
		config["target_url"],
		] + get_duplicity_additional_args(env) + args,
	get_duplicity_env_vars(env))

def list_target_files(config):
	if config["type"] == "local":
		import urllib.parse
		try:
			url = urllib.parse.urlparse(config["target_url"])
		except ValueError:
			return "invalid target"

		return [(fn, os.path.getsize(os.path.join(url.path, fn))) for fn in os.listdir(url.path)]

	elif config["type"] == "rsync":
		import urllib.parse
		try:
			url = urllib.parse.urlparse(config["target_url"])
		except ValueError:
			return "invalid target"

		rsync_fn_size_re = re.compile(r'.*    ([^ ]*) [^ ]* [^ ]* (.*)')
		rsync_target = '{host}:{path}'

		# Strip off any trailing port specifier because it's not valid in rsync's
		# DEST syntax.  Explicitly set the port number for the ssh transport.
		user_host, *_ = url.netloc.rsplit(':', 1)
		try:
			port = url.port
		except ValueError:
			port = 22

		url_path = url.path
		if not url_path.endswith('/'):
			url_path = url_path + '/'
		if url_path.startswith('/'):
			url_path = url_path[1:]

		rsync_command = [ 'rsync',
					'-e',
					f'/usr/bin/ssh -i /root/.ssh/id_rsa_miab -oStrictHostKeyChecking=no -oBatchMode=yes -p {port}',
					'--list-only',
					'-r',
					rsync_target.format(
						host=user_host,
						path=url_path)
				]

		code, listing = shell('check_output', rsync_command, trap=True, capture_stderr=True)
		if code == 0:
			ret = []
			for l in listing.split('\n'):
				match = rsync_fn_size_re.match(l)
				if match:
					ret.append( (match.groups()[1], int(match.groups()[0].replace(',',''))) )
			return ret
		else:
			if 'Permission denied (publickey).' in listing:
				reason = "Invalid user or check you correctly copied the SSH key."
			elif 'No such file or directory' in listing:
				reason = "Provided path {} is invalid.".format(url_path)
			elif 'Network is unreachable' in listing:
				reason = "The IP address {} is unreachable.".format(url.hostname)
			elif 'Could not resolve hostname' in listing:
				reason = "The hostname {} cannot be resolved.".format(url.hostname)
			else:
				reason = "Unknown error." \
						"Please check running 'management/backup.py --verify'" \
						"from mailinabox sources to debug the issue."
			raise ValueError("Connection to rsync host failed: {}".format(reason))

	elif config["type"] == "s3":
		import urllib.parse
		try:
			url = urllib.parse.urlparse(config["target_url"])
		except ValueError:
			return "invalid target"

		import boto3.s3
		from botocore.exceptions import ClientError

		bucket = url.hostname
		path = url.path

		# If no prefix is specified, set the path to '', otherwise boto won't list the files
		if path == '/':
			path = ''

		if bucket == "":
			raise ValueError("Enter an S3 bucket name.")

		# connect to the region & bucket
		try:
			s3 = None
			if "s3_region_name" in config:
				s3 = boto3.client('s3', \
					endpoint_url=config["s3_endpoint_url"], \
					region_name=config["s3_region_name"], \
					aws_access_key_id=config["s3_access_key_id"], \
					aws_secret_access_key=config["s3_secret_access_key"])
			else:
				s3 = boto3.client('s3', \
					endpoint_url=config["s3_endpoint_url"], \
					aws_access_key_id=config["s3_access_key_id"], \
					aws_secret_access_key=config["s3_secret_access_key"])

			bucket_objects = s3.list_objects_v2(Bucket=bucket, Prefix=path)['Contents']
			backup_list = [(key['Key'][len(path):], key['Size']) for key in bucket_objects]
		except ClientError as e:
			raise ValueError(e)
		return backup_list

	elif config["type"] == "b2":
		import urllib.parse
		try:
			url = urllib.parse.urlparse(config["target_url"])
		except ValueError:
			return "invalid target"


		from b2sdk.v1 import InMemoryAccountInfo, B2Api
		from b2sdk.v1.exception import NonExistentBucket
		info = InMemoryAccountInfo()
		b2_api = B2Api(info)

		# Extract information from target
		b2_application_keyid = url.netloc[:url.netloc.index(':')]
		b2_application_key = url.netloc[url.netloc.index(':')+1:url.netloc.index('@')]
		b2_bucket = url.netloc[url.netloc.index('@')+1:]

		try:
			b2_api.authorize_account("production", b2_application_keyid, b2_application_key)
			bucket = b2_api.get_bucket_by_name(b2_bucket)
		except NonExistentBucket as e:
			raise ValueError("B2 Bucket does not exist. Please double check your information!")
		return [(key.file_name, key.size) for key, _ in bucket.ls()]

	else:
		raise ValueError(config["type"])


def set_off_backup_config(env):
	config = {
		"type": "off"
	}

	write_backup_config(env, config)

	return "OK"

def set_local_backup_config(env, min_age_in_days):
	# min_age_in_days must be an int
	if isinstance(min_age_in_days, str):
		min_age_in_days = int(min_age_in_days)

	config = {
		"type": "local",
		"min_age_in_days": min_age_in_days
	}

	write_backup_config(env, config)

	return "OK"

def set_rsync_backup_config(env, min_age_in_days, target_url):
	# min_age_in_days must be an int
	if isinstance(min_age_in_days, str):
		min_age_in_days = int(min_age_in_days)

	config = {
		"type": "rsync",
		"target_url": target_url,
		"min_age_in_days": min_age_in_days
	}

	# Validate.
	try:
		list_target_files(config)
	except ValueError as e:
		return str(e)

	write_backup_config(env, config)

	return "OK"

def set_s3_backup_config(env, min_age_in_days, s3_access_key_id, s3_secret_access_key, target_url, s3_endpoint_url, s3_region_name=None):
	# min_age_in_days must be an int
	if isinstance(min_age_in_days, str):
		min_age_in_days = int(min_age_in_days)

	config = {
		"type": "s3",
		"target_url": target_url,
		"s3_endpoint_url": s3_endpoint_url,
		"s3_region_name": s3_region_name,
		"s3_access_key_id": s3_access_key_id,
		"s3_secret_access_key": s3_secret_access_key,
		"min_age_in_days": min_age_in_days
	}

	if s3_region_name is not None:
		config["s3_region_name"] = s3_region_name

	# Validate.
	try:
		list_target_files(config)
	except ValueError as e:
		return str(e)

	write_backup_config(env, config)

	return "OK"

def set_b2_backup_config(env, min_age_in_days, target_url):
	# min_age_in_days must be an int
	if isinstance(min_age_in_days, str):
		min_age_in_days = int(min_age_in_days)

	config = {
		"type": "b2",
		"target_url": target_url,
		"min_age_in_days": min_age_in_days
	}

	# Validate.
	try:
		list_target_files(config)
	except ValueError as e:
		return str(e)

	write_backup_config(env, config)

	return "OK"

def get_backup_config(env):
	backup_root = get_backup_root_directory(env)

	# Defaults.
	config = {
		"type": "local",
		"min_age_in_days": 3
	}

	# Merge in anything written to custom.yaml.
	try:
		with open(os.path.join(backup_root, 'custom.yaml'), 'r') as f:
			custom_config = rtyaml.load(f)
		if not isinstance(custom_config, dict): raise ValueError() # caught below

		# Converting the previous configuration (which was not very clear)
		# into the new configuration format which also provides
		# a "type" attribute to distinguish the type of backup.
		if "type" not in custom_config:
			scheme = custom_config["target"].split(":")[0]
			if scheme == "off":
				custom_config = {
					"type": "off"
				}
			elif scheme == "file":
				custom_config = {
					"type": "local",
					"min_age_in_days": custom_config["min_age_in_days"]
				}
			elif scheme == "rsync":
				custom_config = {
					"type": "rsync",
					"target_url": custom_config["target"],
					"min_age_in_days": custom_config["min_age_in_days"]
				}
			elif scheme == "s3":
				import urllib.parse
				url = urllib.parse.urlparse(custom_config["target"])
				target_url = url.scheme + ":/" + url.path
				s3_endpoint_url = "https://" + url.netloc
				s3_access_key_id = custom_config["target_user"]
				s3_secret_access_key = custom_config["target_pass"]
				custom_config = {
					"type": "s3",
					"target_url": target_url,
					"s3_endpoint_url": s3_endpoint_url,
					"s3_access_key_id": custom_config["target_user"],
					"s3_secret_access_key": custom_config["target_pass"],
					"min_age_in_days": custom_config["min_age_in_days"]
				}
			elif scheme == "b2":
				custom_config = {
					"type": "b2",
					"target_url": custom_config["target"],
					"min_age_in_days": custom_config["min_age_in_days"]
				}
			else:
				raise ValueError("Unexpected scheme during the conversion of the previous config to the new format.")

		config.update(custom_config)
	except:
		pass

	# Adding an implicit information (for "local" backup, the target_url corresponds
	# to the encrypted directory) because in the backup_status function it is easier
	# to pass to duplicity the value of "target_url" without worrying about
	# distinguishing between "local" or "rsync" or "s3" or "b2"  backup types.
	if config["type"] == "local":
		config["target_url"] = "file://" + get_backup_encrypted_directory(env)

	return config

def write_backup_config(env, newconfig):
	with open(get_backup_configuration_file(env), "w") as f:
		f.write(rtyaml.dump(newconfig))

if __name__ == "__main__":
	import sys
	if sys.argv[-1] == "--verify":
		# Run duplicity's verification command to check a) the backup files
		# are readable, and b) report if they are up to date.
		run_duplicity_verification()

	elif sys.argv[-1] == "--list":
		# List the saved backup files.
		for fn, size in list_target_files(get_backup_config(load_environment())):
			print("{}\t{}".format(fn, size))

	elif sys.argv[-1] == "--status":
		# Show backup status.
		ret = backup_status(load_environment())
		print(rtyaml.dump(ret["backups"]))
		print("Storage for unmatched files:", ret["unmatched_file_size"])

	elif len(sys.argv) >= 2 and sys.argv[1] == "--restore":
		# Run duplicity restore. Rest of command line passed as arguments
		# to duplicity. The restore path should be specified.
		run_duplicity_restore(sys.argv[2:])

	else:
		# Perform a backup. Add --full to force a full backup rather than
		# possibly performing an incremental backup.
		full_backup = "--full" in sys.argv
		perform_backup(full_backup)
