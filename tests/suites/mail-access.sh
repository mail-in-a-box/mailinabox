# -*- indent-tabs-mode: t; tab-width: 4; -*-
#

_test_greylisting_x() {
	# helper function sends mail and checks that it was greylisted
	local email_to="$1"
	local email_from="$2"
	
	start_log_capture
	start_mail_capture "$email_to"
	record "[Send mail anonymously TO $email_to FROM $email_from]"
	local output
	output="$($PYMAIL -no-delete -f $email_from -to $email_to '' $PRIVATE_IP '' '' 2>&1)"
	local code=$?
	if [ $code -eq 0 ]; then	
		wait_mail
		local file=( $(get_captured_mail_files) )
		record "[Check captured mail for X-Greylist header]"
		if ! grep "X-Greylist: delayed" <"$file" >/dev/null; then
			record "not found"
			test_failure "message not greylisted - X-Greylist header missing"
			record_captured_mail
		else
			record "found"
		fi
	else
		assert_python_failure $code "$output" "SMTPRecipientsRefused" "Greylisted"
	fi

	check_logs
}


postgrey_reset() {
	# when postgrey receives a message for processing that is suspect,
	# it will:
	#	1. initally reject it
	#	2. after a delay, permit delivery (end entity must resend),
	#	   but with a X-Greyist header	  
	#	3. subsequent deliveries will succeed with no header
	#	   modifications
	#
	# because of #3, reset postgrey to establish a "clean" greylisting
	# testing scenario
	#
	record "[Reset postgrey]"
	if [ ! -d "/var/lib/postgrey" ]; then
		die "Postgrey database directory /var/lib/postgrey does not exist!"
	fi
	systemctl stop postgrey >>$TEST_OF 2>&1 || die "unble to stop postgrey"
	if ! rm -f /var/lib/postgrey/* >>$TEST_OF 2>&1; then
		systemctl start postgrey >>$TEST_OF 2>&1
		die "unable to remove the postgrey database files"
	fi
	systemctl start postgrey >>$TEST_OF 2>&1 || die "unble to start postgrey"
}


test_greylisting() {
	# test that mail is delayed by greylisting
	test_start "greylisting"

	# reset postgrey's database to start the cycle over
	postgrey_reset

	# create standard user alice
	local alice="alice@somedomain.com"
	create_user "$alice" "alice"

	# IMPORTANT: bob's domain must be from one that has no SPF record
	# in DNS. At the time of creation of this script, yahoo.com did
	# not...
	local bob="bob@yahoo.com"
	
	# send to alice anonymously from bob
	_test_greylisting_x "$alice" "$bob"
	
	delete_user "$alice"
	test_end
}


test_relay_prohibited() {
	# test that the server does not relay
	test_start "relay-prohibited"

	start_log_capture
	record "[Attempt relaying mail anonymously]"
	local output
	output="$($PYMAIL -no-delete -f joe@badguy.com -to naive@gmail.com '' $PRIVATE_IP '' '' 2>&1)"
	assert_python_failure $? "$output" "SMTPRecipientsRefused" "Relay access denied"
	check_logs

	test_end
}


test_spf() {
	# test mail rejection due to SPF policy of FROM address
	test_start "spf"
	
	# create standard user alice
	local alice="alice@somedomain.com"
	create_user "$alice" "alice"

	# who we will impersonate
	local from="test@google.com"
	local domain=$(awk -F@ '{print $2}' <<<"$from")

	# send to alice anonymously from imposter
	start_log_capture
	start_mail_capture "$alice"
	record "[Test SPF for $domain FROM $from TO $alice]"
	local output
	output="$($PYMAIL -no-delete -f $from -to $alice '' $PRIVATE_IP '' '' 2>&1)"
	local code=$?
	if ! assert_python_failure $code "$output" "SMTPRecipientsRefused" "SPF" && [ $code -eq 0 ]
	then
		wait_mail
		record_captured_mail
	fi
	check_logs
	
	delete_user "$alice"
	test_end
}


test_mailbox_pipe() {
	# postfix allows piped commands in aliases for local processing,
	# which is a serious security issue. test that pipes are not
	# permitted or don't work
	test_start "mailbox-pipe"
	
	# create standard user alice
	local alice="alice@somedomain.com"
	create_user "$alice" "alice"
	local alice_dn="$ATTR_DN"

	# create the program to handle piped mail
	local cmd="/tmp/pipedrop.$$.sh"
	local outfile="/tmp/pipedrop.$$.out"
	cat 2>>$TEST_OF >$cmd <<EOF
#!/bin/bash
cat > $outfile
EOF
	chmod 755 $cmd
	rm -f $outfile
	
	# add a piped maildrop
	record "[Add pipe command as alice's maildrop]"
	ldapmodify -H $LDAP_URL -x -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" >>$TEST_OF 2>&1 <<EOF
dn: $alice_dn
replace: maildrop
maildrop: |$cmd
EOF
	[ $? -ne 0 ] && die "Could not modify ${alice}'s maildrop"

	# send an email message to alice
	start_log_capture
	record "[Send an email to $alice - test pipe]"
	local output
	output="$($PYMAIL -no-delete $PRIVATE_IP $alice alice 2>&1)"
	local code=$?
	
	if [ $code -ne 0 ]; then
		assert_python_failure $code "$output" SMTPAuthenticationError
		check_logs
	else
		sleep 5
		if grep_postfix_log "User doesn't exist: |$cmd@"; then
			# ok
			check_logs
		else
			assert_check_logs
		fi
		
		if [ -e $outfile ]; then
			test_failure "a maildrop containing a pipe was executed by postfix"
		fi
	fi
	
	delete_user "$alice"
	rm -f $cmd
	rm -f $outfile
	
	test_end

}


suite_start "mail-access" ensure_root_user

test_greylisting
test_relay_prohibited
test_spf
test_mailbox_pipe

suite_end
