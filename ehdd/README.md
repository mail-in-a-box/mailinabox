# Encryption-at-rest support

This directory contains support for encryption-at-rest of the
user-data directory. Also known as STORAGE_ROOT, the user-data
directory is typically located at /home/user-data, and is where
non-system data is stored, like email, ssl certificates, backups, etc.

Encryption-at-rest of STORAGE_ROOT is provided by a LUKS formatted
hard disk (file) created and stored at /home/user-data.HDD.

To enable encryption-at-rest ON A FRESH INSTALL, you must run
`ehdd/setup-encrypted.sh` instead of setup/start.sh. This will set
things up by creating and mounting the encypted disk for
/home/user-data. Once created and mounted, setup/start.sh is run to
continue normal setup operation.

At the end of setup, services that utilize /home/user-data will be
disabled from starting automatically after a reboot (because
/home/user-data will not have been mounted). Run `ehdd/run-this-after-reboot.sh`
after a reboot to remount the encrypted hard drive and launch the
disabled services.

Do not forget your encryption passphrase - otherwise your
/home/user-data files will be unrecoverable!

For a non-interactive install, setting EHDD_GB will create a luks
drive of that size without prompting, and EHDD_KEYFILE must be set to
a file containing the encryption key (the file should not have any
newlines). DO NOT USE A KEYFILE ON A PRODUCTION MACHINE.

To upgrade a system to encryption-at-rest, shut down all services that
use STORAGE_ROOT (postfix, dovecot, slapd, etc). Rename STORAGE_ROOT
to something else. Run ehdd/create_hdd.sh, then ehdd/mount.sh. Copy or
move the contents of the renamed directory to STORAGE_ROOT. Restart
all services.
