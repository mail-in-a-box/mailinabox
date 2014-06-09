#!/usr/bin/python3

# This script performs a backup of all user data:
# 1) System services are stopped while a copy of user data is made.
# 2) An incremental backup is made using rdiff-backup into the
#    directory STORAGE_ROOT/backup/rdiff-history. This directory
#    will contain the latest files plus a complete history for
#    all prior backups.
# 3) The stopped services are restarted.
# 4) The backup directory is compressed into a single file using tar.
# 5) That file is encrypted with a long password stored in backup/secret_key.txt.

import os, os.path, subprocess

from utils import exclusive_process, load_environment, shell

env = load_environment()

exclusive_process("backup")

# Ensure the backup directory exists.
backup_dir = os.path.join(env["STORAGE_ROOT"], 'backup')
rdiff_backup_dir = os.path.join(backup_dir, 'rdiff-history')
os.makedirs(backup_dir, exist_ok=True)

# Stop services.
shell('check_call', ["/usr/sbin/service", "dovecot", "stop"])
shell('check_call', ["/usr/sbin/service", "postfix", "stop"])

# Update the backup directory which stores increments.
try:
	shell('check_call', [
		"/usr/bin/rdiff-backup",
		"--exclude", backup_dir,
	 	env["STORAGE_ROOT"],
	 	rdiff_backup_dir])
except subprocess.CalledProcessError:
	# Trap the error so we restart services again.
	pass

# Start services.
shell('check_call', ["/usr/sbin/service", "dovecot", "start"])
shell('check_call', ["/usr/sbin/service", "postfix", "start"])

# Tar the rdiff-backup directory into a single file.
shell('check_call', [
	"/bin/tar",
	"-zc",
	"-f", os.path.join(backup_dir, "latest.tgz"),
	"-C", rdiff_backup_dir,
	"."])

# Encrypt the backup using the backup private key.
shell('check_call', [
	"/usr/bin/openssl",
	"enc",
	"-aes-256-cbc",
	"-a",
	"-salt",
	"-in", os.path.join(backup_dir, "latest.tgz"),
	"-out", os.path.join(backup_dir, "latest.tgz.enc"),
	"-pass", "file:%s" % os.path.join(backup_dir, "secret_key.txt"),
	])

# The backup can be decrypted with:
# openssl enc -d -aes-256-cbc -a -in latest.tgz.enc -out /dev/stdout -pass file:secret_key.txt | tar -z
