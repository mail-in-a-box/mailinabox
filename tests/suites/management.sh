# -*- indent-tabs-mode: t; tab-width: 4; -*-
#	

test_perform_backup() {
	# make sure backups work
	#
	test_start "perform_backup"
	record "[create custom.yaml]"
	cat >$STORAGE_ROOT/backup/custom.yaml <<EOF
min_age_in_days: 1
target: local
EOF
	record "[run management/backup.py]"
	pushd "$MIAB_DIR" >/dev/null 2>>$TEST_OF \
		|| test_failure "could not change directory to miab root"
	local output code
	output=$(management/backup.py 2>&1)
	code=$?
	echo "$output" >> $TEST_OF
	if [ $code -ne 0 ]; then
		test_failure $(python_error "$output")
		test_failure "backup failed"
	fi
	popd >/dev/null 2>>$TEST_OF
	rm -f $STORAGE_ROOT/backup/custom.yaml
	test_end
}

suite_start "management"

test_perform_backup

suite_end
