# -*- indent-tabs-mode: t; tab-width: 4; -*-
# mail alias tests
#

test_shared_user_alias_login() {
	# a login attempt should fail when using 'mail' aliases that map
	# to two or more users
	
	test_start "shared-user-alias-login"
	# create standard users alice and bob
	local alice="alice@somedomain.com"
	local bob="bob@anotherdomain.com"
	create_user "$alice" "alice"
	local alice_dn="$ATTR_DN"
	create_user "$bob" "bob"
	local bob_dn="$ATTR_DN"

	# add common alias to alice and bob
	local alias="us@somedomain.com"
	add_alias $alice_dn $alias user
	add_alias $bob_dn $alias user

	start_log_capture
	record "[Log in as alias to postfix]"
	local output
	local subject="Mail-In-A-Box test $(generate_uuid)"
	
	# login as the alias to postfix - should fail
	output="$($PYMAIL -subj "$subject" -no-delete $PRIVATE_IP $alias alice 2>&1)"
	assert_python_failure $? "$output" "SMTPAuthenticationError"

	# login as the alias to dovecot - should fail
	record "[Log in as alias to dovecot]"
	local timeout=""
	if have_test_failures; then
		timeout="-timeout 0"
	fi
	output="$($PYMAIL -subj "$subject" $timeout -no-send $PRIVATE_IP $alias alice 2>&1)"
	assert_python_failure $? "$output" "authentication failure"

	check_logs

	delete_user "$alice"
	delete_user "$bob"
	test_end
}


test_alias_group_member_login() {
	# a login attempt should fail when using an alias defined in a
	# mailGroup type alias
	
	test_start "alias-group-member-login"
	# create standard user alice
	local alice="alice@somedomain.com"
	create_user "$alice" "alice"
	local alice_dn="$ATTR_DN"

	# create alias group with alice in it
	local alias="us@somedomain.com"
	create_alias_group "$alias" "$alice_dn"

	start_log_capture
	record "[Log in as alias to postfix]"
	local output
	local subject="Mail-In-A-Box test $(generate_uuid)"
	
	# login as the alias to postfix - should fail
	output="$($PYMAIL -subj "$subject" -no-delete $PRIVATE_IP $alias alice 2>&1)"
	assert_python_failure $? "$output" "SMTPAuthenticationError"

	# login as the alias to dovecot - should fail
	record "[Log in as alias to dovecot]"
	local timeout=""
	if have_test_failures; then
		timeout="-timeout 0"
	fi
	output="$($PYMAIL -subj "$subject" $timeout -no-send $PRIVATE_IP $alias alice 2>&1)"
	assert_python_failure $? "$output" "AUTHENTICATIONFAILED"

	check_logs

	delete_user "$alice"
	delete_alias_group "$alias"
	test_end
}


test_shared_alias_delivery() {
	# mail sent to the shared alias of two users (eg. postmaster),
	# should be sent to both users
	test_start "shared-alias-delivery"
	# create standard users alice, bob, and mary
	local alice="alice@somedomain.com"
	local bob="bob@anotherdomain.com"
	local mary="mary@anotherdomain.com"
	create_user "$alice" "alice"
	local alice_dn="$ATTR_DN"
	create_user "$bob" "bob"
	local bob_dn="$ATTR_DN"
	create_user "$mary" "mary"

	# add common alias to alice and bob
	local alias="us@somedomain.com"
	create_alias_group $alias $alice_dn $bob_dn

	# login as mary and send to alias
	start_log_capture
	record "[Sending mail to alias]"
	local output
	local subject="Mail-In-A-Box test $(generate_uuid)"
	output="$($PYMAIL -subj "$subject" -no-delete -to $alias na $PRIVATE_IP $mary mary 2>&1)"
	if assert_python_success $? "$output"; then
		# check that alice and bob received it by deleting the mail in
		# both mailboxes
		record "[Delete mail alice's mailbox]"
		output="$($PYMAIL -subj "$subject" -no-send $PRIVATE_IP $alice alice 2>&1)"
		assert_python_success $? "$output"
		record "[Delete mail bob's mailbox]"
		output="$($PYMAIL -subj "$subject" -no-send $PRIVATE_IP $bob bob 2>&1)"
		assert_python_success $? "$output"
	fi

	assert_check_logs
	
	delete_user "$alice"
	delete_user "$bob"
	delete_user "$mary"
	delete_alias_group $alias
	test_end

}


test_trial_nonlocal_alias_delivery() {
	# verify that mail sent to an alias with a non-local address
	# (rfc822MailMember) can be delivered
	test_start "trial-nonlocal-alias-delivery"

	# add alias
	local alias="external@somedomain.com"
	create_alias_group $alias "test@google.com"

	# trail send...doesn't actually get delivered
	start_log_capture
	sendmail_bv_send "$alias" 120
	assert_check_logs
	have_test_failures && record_captured_mail
	delete_alias_group $alias
	test_end
}




test_catch_all() {
	# 1. ensure users in the catch-all alias receive messages to
	# invalid users for handled domains
	#
	# 2. ensure sending mail to valid user does not go to catch-all
	#
	test_start "catch-all"
	# create standard users alice, bob, and mary
	local alice="alice@somedomain.com"
	local bob="bob@anotherdomain.com"
	local mary="mary@anotherdomain.com"
	create_user "$alice" "alice"
	local alice_dn="$ATTR_DN"
	create_user "$bob" "bob"
	local bob_dn="$ATTR_DN"
	create_user "$mary" "mary"

	# add catch-all alias to alice and bob
	local alias="@somedomain.com"
	create_alias_group $alias $alice_dn $bob_dn

	# login as mary, then send to an invalid address. alice and bob
	# should receive that mail because they're aliases to the
	# catch-all for the domain
	record "[Sending mail to invalid user at catch-all domain]"
	start_log_capture
	local output
	local subject="Mail-In-A-Box test $(generate_uuid)"
	output="$($PYMAIL -subj "$subject" -no-delete -to INVALID${alias} na $PRIVATE_IP $mary mary 2>&1)"
	if assert_python_success $? "$output"; then
		# check that alice and bob received it by deleting the mail in
		# both mailboxes
		record "[Delete mail in alice's and bob's mailboxes]"
		output="$($PYMAIL -subj "$subject" -no-send $PRIVATE_IP $alice alice 2>&1)"
		assert_python_success $? "$output"
		output="$($PYMAIL -subj "$subject" -no-send $PRIVATE_IP $bob bob 2>&1)"
		assert_python_success $? "$output"
	fi
	assert_check_logs

	# login as mary and send to a valid address at the catch-all
	# domain. that user should receive it and the catch-all should not
	record "[Sending mail to valid user at catch-all domain]"
	start_log_capture
	subject="Mail-In-A-Box test $(generate_uuid)"
	output="$($PYMAIL -subj "$subject" -to $alice alice $PRIVATE_IP $mary mary 2>&1)"
	if assert_python_success $? "$output"; then
		# alice got the mail and it was deleted
		# make sure bob didn't also receive the message
		record "[Delete mail in bob's mailbox]"
		output="$($PYMAIL -timeout 10 -subj "$subject" -no-send $PRIVATE_IP $bob bob 2>&1)"
		assert_python_failure $? "$output" "TimeoutError"
	fi
	assert_check_logs

	delete_user "$alice"
	delete_user "$bob"
	delete_user "$mary"
	delete_alias_group $alias
	test_end
}


test_nested_alias_groups() {
	# sending to an alias with embedded aliases should reach final
	# recipients
	test_start "nested-alias-groups"
	# create standard users alice and bob
	local alice="alice@zdomain.z"
	create_user "$alice" "alice"
	local alice_dn="$ATTR_DN"
	local bob="bob@zdomain.z"
	create_user "$bob" "bob"
	local bob_dn="$ATTR_DN"

	# add nested alias groups [ alias1 -> alias2 -> alice ]
	local alias1="z1@xyzdomain.z"
	local alias2="z2@xyzdomain.z"
	create_alias_group $alias2 $alice_dn
	create_alias_group $alias1 $ATTR_DN

	# send to alias1 from bob, then ensure alice received it
	record "[Sending mail to alias $alias1]"
	start_log_capture
	local output
	local subject="Mail-In-A-Box test $(generate_uuid)"
	output="$($PYMAIL -subj "$subject" -no-delete -to $alias1 na $PRIVATE_IP $bob bob 2>&1)"
	if assert_python_success $? "$output"; then
		record "[Test delivery - delete mail in alice's mailbox]"
		output="$($PYMAIL -subj "$subject" -no-send $PRIVATE_IP $alice alice 2>&1)"
		assert_python_success $? "$output"
	fi

	assert_check_logs

	delete_user "$alice"
	delete_user "$bob"
	delete_alias_group "$alias1"
	delete_alias_group "$alias2"
	
	test_end
}

test_user_rename() {
	# test the use case where someone's name changed
	# in this test we rename the user's 'mail' address, but
	# leave maildrop as-is
	test_start "user-rename"

	# create standard user alice
	local alice1="alice.smith@somedomain.com"
	local alice2="alice.jones@somedomain.com"
	create_user "$alice1" "alice"
	local alice_dn="$ATTR_DN"
	local output

	# send email to alice with subject1
	record "[Testing mail to alice1]"
	local subject1="Mail-In-A-Box test $(generate_uuid)"
	local success1=false
	start_mail_capture "$alice1"
	record "[Sending mail to $alice1]"
	output="$($PYMAIL -subj "$subject1" -no-delete $PRIVATE_IP $alice1 alice 2>&1)"
	assert_python_success $? "$output" && success1=true

	# alice1 got married, add a new mail address alice2
	wait_mail	# rename too soon, and the first message is bounced
	record "[Changing alice's mail address]"
	ldapmodify -H $LDAP_URL -x -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" >>$TEST_OF 2>&1 <<EOF
dn: $alice_dn
replace: mail
mail: $alice2
EOF
	[ $? -ne 0 ] && die "Unable to modify ${alice1}'s mail address!"

	# send email to alice with subject2
	start_log_capture
	local subject2="Mail-In-A-Box test $(generate_uuid)"
	local success2=false
	record "[Sending mail to $alice2]"
	output="$($PYMAIL -subj "$subject2" -no-delete $PRIVATE_IP $alice2 alice 2>&1)"
	assert_python_success $? "$output" && success2=true
	assert_check_logs

	# delete both messages
	if $success1; then
		record "[Deleting mail 1]"
		output="$($PYMAIL -subj "$subject1" -no-send $PRIVATE_IP $alice2 alice 2>&1)"
		assert_python_success $? "$output"
	fi

	if $success2; then
		record "[Deleting mail 2]"
		output="$($PYMAIL -subj "$subject2" -no-send $PRIVATE_IP $alice2 alice 2>&1)"
		assert_python_success $? "$output"
	fi

	delete_user "$alice2"
	test_end
}



suite_start "mail-aliases"

test_shared_user_alias_login
test_alias_group_member_login
test_shared_alias_delivery	 # local alias delivery
test_trial_nonlocal_alias_delivery
test_catch_all
test_nested_alias_groups
test_user_rename

suite_end
