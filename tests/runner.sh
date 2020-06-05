#!/bin/bash
# -*- indent-tabs-mode: t; tab-width: 4; -*-

#
# Runner for test suites
#

# operate from the runner's directory
cd "$(dirname $0)"

# load global functions and variables
. suites/_init.sh

runner_suites=(
	ldap-connection
	ldap-access
	mail-basic
	mail-from
	mail-aliases
	mail-access
	management-users
)

usage() {
	echo ""
	echo "Usage: $(basename $0) [-failfatal] [suite-name ...]"
	echo "Valid suite names:"
	for runner_suite in ${runner_suites[@]}; do
		echo "	 $runner_suite"
	done
	echo "If no suite-name(s) given, all suites are run"
	echo ""
	echo "Options:"
	echo "  -failfatal	    The runner will stop if any test fails"
	echo "  -dumpoutput     After all tests have run, dump all failed test output"
	echo "  -no-smtp-remote Skip tests requiring a remote SMTP server"
	echo ""
	echo "Output directory: $(dirname $0)/${base_outputdir}"
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
			if array_contains "$1" ${runner_suites[@]}; then
				. "suites/$1.sh"
			else
				echo "Unknown suite '$1'" 1>&2
				usage
			fi
			;;
	esac
	shift
done

# if no suites specified on command line, run all suites
if [ $OVERALL_COUNT_SUITES -eq 0 ]; then
	rm -rf "${base_outputdir}"
	for runner_suite in ${runner_suites[@]}; do
		. suites/$runner_suite.sh
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
