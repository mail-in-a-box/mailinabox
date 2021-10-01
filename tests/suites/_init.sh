# -*- indent-tabs-mode: t; tab-width: 4; -*-

. lib/all.sh "lib"      || exit 1

# globals - all global variables are UPPERCASE
ASSETS_DIR="assets"
BASE_OUTPUTDIR="$(realpath out)/$(hostname | awk -F. '{print $1}')"
declare -i OVERALL_SUCCESSES=0
declare -i OVERALL_FAILURES=0
declare -i OVERALL_SKIPPED=0
declare -i OVERALL_COUNT=0
declare -i OVERALL_COUNT_SUITES=0

# options
FAILURE_IS_FATAL=no
DUMP_FAILED_TESTS_OUTPUT=no

# record a list of output files for failed tests
FAILED_TESTS_MANIFEST="$BASE_OUTPUTDIR/failed_tests_manifest.txt"
rm -f "$FAILED_TESTS_MANIFEST"


suite_start() {
	let TEST_NUM=1
	let SUITE_COUNT_SUCCESS=0
	let SUITE_COUNT_FAILURE=0
	let SUITE_COUNT_SKIPPED=0
	let SUITE_COUNT_TOTAL=0
	SUITE_NAME="$1"
	SUITE_START=$(date +%s)
	OUTDIR="$BASE_OUTPUTDIR/$SUITE_NAME"
	mkdir -p "$OUTDIR"
	echo ""
	echo "Starting suite: $SUITE_NAME"
	shift
	suite_setup "$@"
}

suite_end() {
	suite_cleanup "$@"
	local SUITE_END=$(date +%s)
	echo "Suite $SUITE_NAME finished ($(elapsed_pretty $SUITE_START $SUITE_END))"
	let OVERALL_SUCCESSES+=$SUITE_COUNT_SUCCESS
	let OVERALL_FAILURES+=$SUITE_COUNT_FAILURE
	let OVERALL_SKIPPED+=$SUITE_COUNT_SKIPPED
	let OVERALL_COUNT+=$SUITE_COUNT_TOTAL
	let OVERALL_COUNT_SUITES+=1
}

suite_setup() {
	[ -z "$1" ] && return 0
	TEST_OF="$OUTDIR/setup"
	local script
	for script; do eval "$script";	done
	TEST_OF=""
}

suite_cleanup() {
	[ -z "$1" ] && return 0
	TEST_OF="$OUTDIR/cleanup"
	local script
	for script; do eval "$script"; done
	TEST_OF=""
}

test_start() {
	TEST_DESC="${1:-}"
	TEST_NAME="$(printf "%03d" $TEST_NUM)"
	TEST_OF="$OUTDIR/$TEST_NAME"
	TEST_STATE=""
	TEST_STATE_MSG=()
	echo "TEST-START \"${TEST_DESC:-unnamed}\"" >$TEST_OF
	echo -n "  $TEST_NAME: $TEST_DESC: "
	let TEST_NUM+=1
	let SUITE_COUNT_TOTAL+=1
}

test_end() {
	[ -z "$TEST_OF" ] && return
	if [ $# -gt 0 ]; then
		[ -z "$1" ] && test_success || test_failure "$1"
	fi
	case $TEST_STATE in
		SUCCESS | "" )
			record "[SUCCESS]"
			echo "SUCCESS"
			let SUITE_COUNT_SUCCESS+=1
			;;
		FAILURE )
			record "[FAILURE]"
			echo "${F_DANGER}FAILURE${F_RESET}:"
			local idx=0
			while [ $idx -lt ${#TEST_STATE_MSG[*]} ]; do
				record "${TEST_STATE_MSG[$idx]}"
				echo "	   why: ${TEST_STATE_MSG[$idx]}"
				let idx+=1
			done
			echo "$TEST_OF" >>$FAILED_TESTS_MANIFEST
			echo "	   see: $TEST_OF"
			let SUITE_COUNT_FAILURE+=1
			if [ "$FAILURE_IS_FATAL" == "yes" ]; then
				record "FATAL: failures are fatal option enabled"
				echo "FATAL: failures are fatal option enabled"
				dump_failed_tests_output
				exit 1
			fi
			;;
		SKIPPED )
			record "[SKIPPED]"
			echo "SKIPPED"
			local idx=0
			while [ $idx -lt ${#TEST_STATE_MSG[*]} ]; do
				record "${TEST_STATE_MSG[$idx]}"
				echo "	   why: ${TEST_STATE_MSG[$idx]}"
				let idx+=1
			done
			let SUITE_COUNT_SKIPPED+=1
			;;
		* )
			record "[INVALID TEST STATE '$TEST_STATE']"
			echo "Invalid TEST_STATE=$TEST_STATE"
			let SUITE_COUNT_FAILURE+=1
			;;
	esac
	TEST_OF=""
}

test_success() {
	[ -z "$TEST_OF" ] && return
	[ -z "$TEST_STATE" ] && TEST_STATE="SUCCESS"
}

test_failure() {
	local why="$1"
	[ -z "$TEST_OF" ] && return
	record "** TEST_FAILURE: $why **"
	TEST_STATE="FAILURE"
	TEST_STATE_MSG+=( "$why" )
}

test_skip() {
	local why="$1"
	TEST_STATE="SKIPPED"
	TEST_STATE_MSG+=( "$why" )
}

have_test_failures() {
	[ "$TEST_STATE" == "FAILURE" ] && return 0
	return 1
}

record() {
	if [ ! -z "$TEST_OF" ]; then
		echo "$@" >>$TEST_OF
	else
		echo "$@"
	fi
}

die() {
	record "FATAL: $@"
	test_failure "a fatal error occurred"
	test_end
	echo "FATAL: $@"
	dump_failed_tests_output
	exit 1
}

python_error() {
	# finds tracebacks and outputs just the final error message of
	# each
	local output="$1"
	awk 'BEGIN { TB=0; FOUND=0 } TB==0 && /^Traceback/ { TB=1; FOUND=1; next } TB==1 && /^[^ ]/ { print $0; TB=0 } END { if (FOUND==0) exit 1 }' <<< "$output"
	[ $? -eq 1 ] && echo "$output"
}

copy_or_die() {
	local src="$1"
	local dst="$2"
	cp "$src" "$dst" || die "Unable to copy '$src' => '$dst'"
}

dump_failed_tests_output() {
	if [ "$DUMP_FAILED_TESTS_OUTPUT" == "yes" ]; then
		echo ""
		echo "============================================================"
		echo "OUTPUT OF FAILED TESTS"
		echo "============================================================"
		for file in $(cat $FAILED_TESTS_MANIFEST); do
			echo ""
			echo ""
			echo "--------"
			echo "-------- $file"
			echo "--------"
			cat "$file"
		done
	fi
}


##
## Initialize
##

mkdir -p "$BASE_OUTPUTDIR"

