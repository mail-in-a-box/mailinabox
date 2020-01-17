# -*- indent-tabs-mode: t; tab-width: 4; -*-
#	
# User management tests

_test_mixed_case() {
	# helper function sends multiple email messages to test mixed case
	# input scenarios
	local alices=($1)  # list of mixed-case email addresses for alice
	local bobs=($2)    # list of mixed-case email addresses for bob
	local aliases=($3) # list of mixed-case email addresses for an alias

	start_log_capture

	local alice_pw="$(generate_password 16)"
	local bob_pw="$(generate_password 16)"
	# create local user alice and alias group
	if mgmt_assert_create_user "${alices[0]}" "$alice_pw"; then
		# test that alice cannot also exist at the same time
		if mgmt_create_user "${alices[1]}" "$alice_pw" no; then
			test_failure "Creation of a user with the same email address, but different case, succeeded."
			test_failure "${REST_ERROR}"
		fi
		
		# create an alias group with alice in it
		mgmt_assert_create_alias_group "${aliases[0]}" "${alices[1]}"
	fi

	# create local user bob
	mgmt_assert_create_user "${bobs[0]}" "$bob_pw"
	
	assert_check_logs
	

	# send mail from bob to alice
	#
	if ! have_test_failures; then
		record "[Mailing to alice from bob]"
		start_log_capture
		local output
		output="$($PYMAIL -to ${alices[2]} "$alice_pw" $PRIVATE_IP ${bobs[1]} "$bob_pw" 2>&1)"
		assert_python_success $? "$output"
		assert_check_logs

		# send mail from bob to the alias, ensure alice got it
		#
		record "[Mailing to alias from bob]"
		start_log_capture
		local subject="Mail-In-A-Box test $(generate_uuid)"
		output="$($PYMAIL -subj "$subject" -no-delete -to ${aliases[1]} na $PRIVATE_IP ${bobs[2]} "$bob_pw" 2>&1)"
		assert_python_success $? "$output"
		output="$($PYMAIL -subj "$subject" -no-send $PRIVATE_IP ${alices[3]} "$alice_pw" 2>&1)"
		assert_python_success $? "$output"
		assert_check_logs
		
		# send mail from alice as the alias to bob, ensure bob got it
		#
		record "[Mailing to bob as alias from alice]"
		start_log_capture
		local subject="Mail-In-A-Box test $(generate_uuid)"
		output="$($PYMAIL -subj "$subject" -no-delete -f ${aliases[2]} -to ${bobs[2]} "$bob_pw" $PRIVATE_IP ${alices[4]} "$alice_pw" 2>&1)"
		assert_python_success $? "$output"
		output="$($PYMAIL -subj "$subject" -no-send $PRIVATE_IP ${bobs[3]} "$bob_pw" 2>&1)"
		assert_python_success $? "$output"
		assert_check_logs
	fi

	mgmt_assert_delete_user "${alices[1]}"
	mgmt_assert_delete_user "${bobs[1]}"
	mgmt_assert_delete_alias_group "${aliases[1]}"
}


test_mixed_case_users() {
	# create mixed-case user name
	# add user to alias using different cases
	# send mail from another user to that user - validates smtp, imap, delivery
	# send mail from another user to the alias
	# send mail from that user as the alias to the other user

	test_start "mixed-case-users"
	
	local alices=(alice@mgmt.somedomain.com
				  aLICE@mgmt.somedomain.com
				  aLiCe@mgmt.somedomain.com
				  ALICE@mgmt.somedomain.com
				  alIce@mgmt.somedomain.com)
	local bobs=(bob@mgmt.somedomain.com
				Bob@mgmt.somedomain.com
				boB@mgmt.somedomain.com
				BOB@mgmt.somedomain.com)
	local aliases=(aLICE@mgmt.anotherdomain.com
				   aLiCe@mgmt.anotherdomain.com
				   ALICE@mgmt.anotherdomain.com)

	_test_mixed_case "${alices[*]}" "${bobs[*]}" "${aliases[*]}"
	
	test_end
}


test_mixed_case_domains() {
	# create mixed-case domain names
	# add user to alias using different cases
	# send mail from another user to that user - validates smtp, imap, delivery
	# send mail from another user to the alias
	# send mail from that user as the alias to the other user

	test_start "mixed-case-domains"
	
	local alices=(alice@mgmt.somedomain.com
				  alice@MGMT.somedomain.com
				  alice@mgmt.SOMEDOMAIN.com
				  alice@mgmt.somedomain.COM
				  alice@Mgmt.SomeDomain.Com)
	local bobs=(bob@mgmt.somedomain.com
				bob@MGMT.somedomain.com
				bob@mgmt.SOMEDOMAIN.com
				bob@Mgmt.SomeDomain.com)
	local aliases=(alice@MGMT.anotherdomain.com
				   alice@mgmt.ANOTHERDOMAIN.com
				   alice@Mgmt.AnotherDomain.Com)
	
	_test_mixed_case "${alices[*]}" "${bobs[*]}" "${aliases[*]}"
	
	test_end
}


test_intl_domains() {
	test_start "intl-domains"

	# local intl alias
	local alias="alice@bücher.example"
	local alias_idna="alice@xn--bcher-kva.example"

	# remote intl user / forward-to
	local intl_person="hans@bücher.example"
	local intl_person_idna="hans@xn--bcher-kva.example"

	# local users
	local bob="bob@somedomain.com"
	local bob_pw="$(generate_password 16)"
	local mary="mary@somedomain.com"
	local mary_pw="$(generate_password 16)"

	start_log_capture

	# international domains are not permitted for user accounts
	if mgmt_create_user "$intl_person" "$bob_pw"; then
		test_failure "A user account is not permitted to have an international domain"
		# ensure user is removed as is expected by the remaining tests
		mgmt_delele_user "$intl_person"
		delete_user "$intl_person"
		delete_user "$intl_person_idna"
	fi
	
	# create local users bob and mary
	mgmt_assert_create_user "$bob" "$bob_pw"
	mgmt_assert_create_user "$mary" "$mary_pw"

	# create intl alias with local user bob and intl_person in it
	if mgmt_assert_create_alias_group "$alias" "$bob" "$intl_person"; then
		# examine LDAP server to verify IDNA-encodings
		get_attribute "$LDAP_ALIASES_BASE" "(mail=$alias_idna)" "rfc822MailMember"
		if [ -z "$ATTR_DN" ]; then
			test_failure "IDNA-encoded alias group not found! created as:$alias expected:$alias_idna"
		elif [ "$ATTR_VALUE" != "$intl_person_idna" ]; then
			test_failure "Alias group with user having an international domain was not ecoded properly. added as:$intl_person expected:$intl_person_idna"
		fi
	fi

	# re-create intl alias with local user bob only
	mgmt_assert_create_alias_group "$alias" "$bob"
	
	assert_check_logs

	if ! have_test_failures; then
		# send mail to alias from mary, ensure bob got it
		record "[Sending to intl alias from mary]"
		# note PYMAIL does not do idna conversion - it'll throw
		# "UnicodeEncodeError: 'ascii' codec can't encode character
		# '\xfc' in position 38".
		#
		# we'll have to send to the idna address directly
		start_log_capture
		local subject="Mail-In-A-Box test $(generate_uuid)"
		local output
		output="$($PYMAIL -subj "$subject" -no-delete -to "$alias_idna" na $PRIVATE_IP $mary "$mary_pw" 2>&1)"
		assert_python_success $? "$output"
		output="$($PYMAIL -subj "$subject" -no-send $PRIVATE_IP $bob "$bob_pw" 2>&1)"
		assert_python_success $? "$output"
		assert_check_logs
	fi

	mgmt_assert_delete_alias_group "$alias"
	mgmt_assert_delete_user "$bob"
	mgmt_assert_delete_user "$mary"

	test_end
}


suite_start "management-users" mgmt_start

test_mixed_case_users
test_mixed_case_domains
test_intl_domains

suite_end mgmt_end

