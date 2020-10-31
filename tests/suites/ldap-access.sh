# -*- indent-tabs-mode: t; tab-width: 4; -*-
#
# Access assertions:
#	service accounts, except management:
#	   can bind but not change passwords, including their own
#	   can read all attributes of all users but not userPassword, totpSecret, totpMruTokenTime, totpMruToken, totpLabel
#	   can not write any user attributes, including shadowLastChange
#	   can read config subtree (permitted-senders, domains)
#	   no access to services subtree, except their own dn
#	users:
#	   can bind and change their own password
#	   can read and change their own shadowLastChange
#      no read or write access to user's own totpSecret, totpMruToken, totpMruTokenTime or totpLabel
#	   can read attributess of all users except:
#            mailaccess, totpSecret, totpMruToken, totpMruTokenTime, totpLabel
#	   no access to config subtree
#	   no access to services subtree
#	other:
#	   no anonymous binds to root DSE
#	   no anonymous binds to database
#


test_user_change_password() {
	# users should be able to change their own passwords
	test_start "user-change-password"

	# create regular user with password "alice"
	local alice="alice@somedomain.com"	  
	create_user "$alice" "alice"
	local alice_dn="$ATTR_DN"

	# bind as alice and update userPassword
	assert_w_access "$alice_dn" "$alice_dn" "alice" write "userPassword=$(slappasswd_hash "alice-new")"
	delete_user "$alice"
	test_end
}


test_user_access() {
	# 1. can read attributess of all users except mailaccess, totpSecret, totpMruToken, totpMruTokenTime, totpLabel
	# 2. can read and change their own shadowLastChange
	# 3. no access to config subtree
	# 4. no access to services subtree
	# 5. no read or write access to own totpSecret, totpMruToken, totpMruTokenTime, or totpLabel

	test_start "user-access"

	local totpSecret="12345678901234567890"
	local totpMruToken="94287082"
	local totpLabel="my phone"
	
	# create regular user's alice and bob
	local alice="alice@somedomain.com"
	create_user "alice@somedomain.com" "alice" "" "$totpSecret,$totpMruToken,$totpLabel"
	local alice_dn="$ATTR_DN"

	local bob="bob@somedomain.com"
	create_user "bob@somedomain.com" "bob" "" "$totpSecret,$totpMruToken,$totpLabel"
	local bob_dn="$ATTR_DN"

	# alice should be able to set her own shadowLastChange
	assert_w_access "$alice_dn" "$alice_dn" "alice" write "shadowLastChange=0"

	# test that alice can read her own attributes
	assert_r_access "$alice_dn" "$alice_dn" "alice" read mail maildrop cn sn shadowLastChange
	
	# alice should not have access to her own mailaccess, totpSecret, totpMruToken, totpMruTokenTime or totpLabel, though
	assert_r_access "$alice_dn" "$alice_dn" "alice" no-read mailaccess totpSecret totpMruToken totpMruTokenTime totpLabel

	# test that alice cannot change her own select attributes
	assert_w_access "$alice_dn" "$alice_dn" "alice"

	# test that alice cannot change her own totpSecret, totpMruToken, totpMruTokenTime or totpLabel
	assert_w_access "$alice_dn" "$alice_dn" "alice" no-write "totpSecret=ABC" "totpMruToken=123456" "totpMruTokenTime=123" "totpLabel=x-phone"

	
	# test that alice can read bob's attributes
	assert_r_access "$bob_dn" "$alice_dn" "alice" read mail maildrop cn sn
	
	# alice should not have access to bob's mailaccess, totpSecret, totpMruToken, totpMruTokenTime, or totpLabel
	assert_r_access "$bob_dn" "$alice_dn" "alice" no-read mailaccess totpSecret totpMruToken totpMruTokenTime totpLabel
	
	# test that alice cannot change bob's select attributes
	assert_w_access "$bob_dn" "$alice_dn" "alice"

	# test that alice cannot change bob's attributes
	assert_w_access "$bob_dn" "$alice_dn" "alice" no-write "totpSecret=ABC" "totpMruToken=123456" "totpMruTokenTime=345" "totpLabel=x-phone"


	# test that alice cannot read a service account's attributes
	assert_r_access "$LDAP_POSTFIX_DN" "$alice_dn" "alice"

	# test that alice cannot read config entries
	assert_r_access "dc=somedomain.com,$LDAP_DOMAINS_BASE" "$alice_dn" "alice"
	assert_r_access "$LDAP_PERMITTED_SENDERS_BASE" "$alice_dn" "alice"

	# test that alice cannot find anything searching config
	test_search "$LDAP_CONFIG_BASE" "$alice_dn" "alice"
	[ $SEARCH_DN_COUNT -gt 0 ] && test_failure "Users should not be able to search config"

	# test that alice cannot find anything searching config domains
	test_search "$LDAP_DOMAINS_BASE" "$alice_dn" "alice"
	[ $SEARCH_DN_COUNT -gt 0 ] && test_failure "Users should not be able to search config domains"

	# test that alice cannot find anything searching services
	test_search "$LDAP_SERVICES_BASE" "$alice_dn" "alice"
	[ $SEARCH_DN_COUNT -gt 0 ] && test_failure "Users should not be able to search services"

	delete_user "$alice"
	delete_user "$bob"
	test_end	
}



test_service_change_password() {
	# service accounts should not be able to change other user's
	# passwords
	# service accounts should not be able to change their own password
	test_start "service-change-password"

	# create regular user with password "alice"
	local alice="alice@somedomain.com"	  
	create_user "alice@somedomain.com" "alice"
	local alice_dn="$ATTR_DN"

	# create a test service account
	create_service_account "test" "test"
	local service_dn="$ATTR_DN"

	# update userPassword of user using service account
	assert_w_access "$alice_dn" "$LDAP_POSTFIX_DN" "$LDAP_POSTFIX_PASSWORD" no-write "userPassword=$(slappasswd_hash "alice-new")"

	# update userPassword of service account using service account
	assert_w_access "$service_dn" "$service_dn" "test" no-write "userPassword=$(slappasswd_hash "test-new")"
	
	delete_user "$alice"
	delete_service_account "test"
	test_end
}


test_service_access() {
	# service accounts should have read-only access to all attributes
	# of all users except userPassword
	# can not write any user attributes, include shadowLastChange
	# can read config subtree (permitted-senders, domains)
	# no access to services subtree, except their own dn
	
	test_start "service-access"

	local totpSecret="12345678901234567890"
	local totpMruToken="94287082"
	local totpLabel="my phone"
	
	# create regular user with password "alice"
	local alice="alice@somedomain.com"
	create_user "alice@somedomain.com" "alice" "" "$totpSecret,$totpMruToken,$totpLabel"

	# create a test service account
	create_service_account "test" "test"
	local service_dn="$ATTR_DN"

	# Use service account to find alice
	record "[Use service account to find alice]"
	get_attribute "$LDAP_USERS_BASE" "mail=${alice}" dn sub "$LDAP_POSTFIX_DN" "$LDAP_POSTFIX_PASSWORD"
	if [ -z "$ATTR_DN" ]; then
		test_failure "Unable to search for user account using service account"
	else
		local alice_dn="$ATTR_DN"
		
		# set shadowLastChange on alice's entry (to test reading it back)
		assert_w_access "$alice_dn" "$alice_dn" "alice" write "shadowLastChange=0"
		
		# check that service account can read user attributes
		assert_r_access "$alice_dn" "$LDAP_POSTFIX_DN" "$LDAP_POSTFIX_PASSWORD" read mail maildrop uid cn sn shadowLastChange
		
		# service account should not be able to read user's userPassword, totpSecret, totpMruToken, totpMruTokenTime, or totpLabel
		assert_r_access "$alice_dn" "$LDAP_POSTFIX_DN" "$LDAP_POSTFIX_PASSWORD" no-read userPassword totpSecret totpMruToken totpMruTokenTime totpLabel

		# service accounts cannot change user attributes
		assert_w_access "$alice_dn" "$LDAP_POSTFIX_DN" "$LDAP_POSTFIX_PASSWORD"
		assert_w_access "$alice_dn" "$LDAP_POSTFIX_DN" "$LDAP_POSTFIX_PASSWORD" no-write "shadowLastChange=1" "totpSecret=ABC" "totpMruToken=333333" "totpMruTokenTime=123" "totpLabel=x-phone"
	fi

	# service accounts can read config subtree (permitted-senders, domains)
	assert_r_access "dc=somedomain.com,$LDAP_DOMAINS_BASE" "$LDAP_POSTFIX_DN" "$LDAP_POSTFIX_PASSWORD" read dc

	# service accounts can search and find things in the config subtree
	test_search "$LDAP_CONFIG_BASE" "$LDAP_POSTFIX_DN" "$LDAP_POSTFIX_PASSWORD" sub
	[ $SEARCH_DN_COUNT -lt 4 ] && test_failure "Service accounts should be able to search config"

	# service accounts can read attributes in their own dn
	assert_r_access "$LDAP_POSTFIX_DN" "$LDAP_POSTFIX_DN" "$LDAP_POSTFIX_PASSWORD" read cn description
	# ... but not userPassword
	assert_r_access "$LDAP_POSTFIX_DN" "$LDAP_POSTFIX_DN" "$LDAP_POSTFIX_PASSWORD" no-read userPassword

	# services cannot read other service's attributes
	assert_r_access "$service_dn" "$LDAP_POSTFIX_DN" "$LDAP_POSTFIX_PASSWORD" no-read cn description userPassword

	delete_user "$alice"
	delete_service_account "test"
	test_end
}


test_root_dse() {
	# no anonymous binds to root dse
	test_start "root-dse"

	record "[bind anonymously to root dse]"
	ldapsearch -H $LDAP_URL -x -b "" -s base >>$TEST_OF 2>&1
	local r=$?
	if [ $r -eq 0 ]; then
		test_failure "Anonymous access to root dse should not be permitted"
	elif [ $r -eq 48 ]; then
		# 48=inappropriate authentication (anon binds not allowed)
		test_success
	else
		die "Error accessing root dse"
	fi
	test_end
}

test_anon_bind() {
	test_start "anon-bind"

	record "[bind anonymously to $LDAP_BASE]"
	ldapsearch -H $LDAP_URL -x -b "$LDAP_BASE" -s base >>$TEST_OF 2>&1
	local r=$?
	if [ $r -eq 0 ]; then
		test_failure "Anonymous access should not be permitted"
	elif [ $r -eq 48 ]; then
		# 48=inappropriate authentication (anon binds not allowed)
		test_success
	else
		die "Error accessing $LDAP_BASE"
	fi

	test_end
}



suite_start "ldap-access"

test_user_change_password
test_user_access
test_service_change_password
test_service_access
test_root_dse
test_anon_bind

suite_end
