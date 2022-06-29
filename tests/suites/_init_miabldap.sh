# load useful functions from setup
. ../setup/functions.sh || exit 1
. ../setup/functions-ldap.sh || exit 1
set +eu

# load test suite helper functions
. suites/_ldap-functions.sh || exit 1
. suites/_mail-functions.sh || exit 1
. suites/_mgmt-functions.sh || exit 1
. suites/_zpush-functions.sh || exit 1


MIAB_DIR=".."
PYMAIL="./test_mail.py"


# options
SKIP_REMOTE_SMTP_TESTS=no
DETECT_SLAPD_LOG_ERROR_OUTPUT=brief
DETECT_SYSLOG_ERROR_OUTPUT=normal


skip_test() {
	# call from within a test to check whether the test will be
	# skipped
	#
	# returns 0 if the current test was skipped in which case your test
	# function must immediately call 'test_end' and return
	#
	if [ "$SKIP_REMOTE_SMTP_TESTS" == "yes" ] &&
		   array_contains "remote-smtp" "$@";
	then
		test_skip "no-smtp-remote option given"
		return 0
	fi
	
	return 1
}



#
# load global vars
#

. /etc/mailinabox.conf || die "Could not load '/etc/mailinabox.conf'"
. "${STORAGE_ROOT}/ldap/miab_ldap.conf" || die "Could not load miab_ldap.conf"
