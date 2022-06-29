#!/bin/bash
# -*- indent-tabs-mode: t; tab-width: 4; -*-

#
# Runner for test suites
#

# operate from the runner's directory
cd "$(dirname $0)"

# load global functions and variables
. suites/_init.sh
. suites/_init_miabldap.sh

default_suites=(
	ldap-connection
	ldap-access
	mail-basic
	mail-from
	mail-aliases
	mail-access
	management-users
	z-push
)

extra_suites=(
	ehdd
	remote-nextcloud
	"upgrade-<name>"
)

usage() {
	echo ""
	echo "Usage: $(basename $0) [options] [suite-name ...]"
	echo "Run QA tests"

	echo ""
	echo "Default test suites:"
	echo "--------------------"
	for runner_suite in ${default_suites[@]}; do
		echo "  $runner_suite"
	done

	echo ""
	echo "Extra test suites:"
	echo "------------------"
	echo "  ehdd               : test encryption-at-rest"
	echo "  remote-nextcloud   : test the setup mod for remote Nextcloud"
	echo "  upgrade-<name>     : verify an upgrade using named populate data"
	echo ""

	echo "If no suite-name(s) are given, all default suites are run"
	echo ""
	echo "Options:"
	echo "--------"
	echo "  -failfatal	    The runner will stop if any test fails"
	echo "  -dumpoutput     After all tests have run, dump all failed test output"
	echo "  -no-smtp-remote Skip tests requiring a remote SMTP server"
	echo ""
	echo "Output directory: ${BASE_OUTPUTDIR}"
	echo ""
	exit 1
}

# process command line
while [ $# -gt 0 ]; do
	case "$1" in
		-failfatal )
			# failure is fatal (via global option, see _init.sh)
			FAILURE_IS_FATAL=yes
			;;
		-dumpoutput )
			DUMP_FAILED_TESTS_OUTPUT="yes"
			;;
		-no-smtp-remote )
			SKIP_REMOTE_SMTP_TESTS="yes"
			;;
		-* )
			echo "Invalid argument $1" 1>&2
			usage
			;;
		* )
			# run named suite
			if [ $OVERALL_COUNT_SUITES -eq 0 ]; then
				rm -rf "${BASE_OUTPUTDIR}"
			fi

			case "$1" in
				default )
					# run all default suites
					for suite in ${default_suites[@]}; do
						. suites/$suite.sh
					done
					;;
				upgrade-* )
					# run upgrade suite with named populate data
					. "suites/upgrade.sh" "$(awk -F- '{print $2}' <<< "$1")"
					;;
				* )
					if array_contains "$1" "${default_suites[@]}" || \
							array_contains "$1" "${extra_suites[@]}"
					then
						# run specified suite
						. "suites/$1.sh"
					else
						echo "Unknown suite '$1'" 1>&2
						usage
					fi
					;;
			esac
	esac
	shift
done

# if no suites specified on command line, run all default suites
if [ $OVERALL_COUNT_SUITES -eq 0 ]; then
	rm -rf "${BASE_OUTPUTDIR}"
	for suite in ${default_suites[@]}; do
		. suites/$suite.sh
	done
fi

echo ""
echo "Done"
echo "$OVERALL_COUNT tests ($OVERALL_SUCCESSES success/$OVERALL_FAILURES failures/$OVERALL_SKIPPED skipped) in $OVERALL_COUNT_SUITES test suites"


if [ $OVERALL_FAILURES -gt 0 ]; then
	dump_failed_tests_output
	exit 1
	
else
	exit 0
fi
