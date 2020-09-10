# -*- indent-tabs-mode: t; tab-width: 4; -*-

# Available REST calls:
#
# general curl format:
# curl -X <b>VERB</b> [-d "<b>parameters</b>"] --user {email}:{password} https://{{hostname}}/admin/mail/users[<b>action</b>]

# ALIASES:
# curl -X GET https://{{hostname}}/admin/mail/aliases?format=json
# curl -X POST -d "address=new_alias@mydomail.com" -d "forwards_to=my_email@mydomain.com" https://{{hostname}}/admin/mail/aliases/add
# curl -X POST -d "address=new_alias@mydomail.com" https://{{hostname}}/admin/mail/aliases/remove

# USERS:
# curl -X GET https://{{hostname}}/admin/mail/users?format=json
# curl -X POST -d "email=new_user@mydomail.com" -d "password=s3curE_pa5Sw0rD" https://{{hostname}}/admin/mail/users/add
# curl -X POST -d "email=new_user@mydomail.com" https://{{hostname}}/admin/mail/users/remove
# curl -X POST -d "email=new_user@mydomail.com" -d "privilege=admin" https://{{hostname}}/admin/mail/users/privileges/add
# curl -X POST -d "email=new_user@mydomail.com" https://{{hostname}}/admin/mail/users/privileges/remove


mgmt_start() {
	# Must be called before performing any REST calls
	local domain="${1:-somedomain.com}"
	MGMT_ADMIN_EMAIL="test_admin@$domain"
	MGMT_ADMIN_PW="$(generate_password)"

	delete_user "$MGMT_ADMIN_EMAIL"
	
	record "[Creating a new account with admin rights for management tests]"
	create_user "$MGMT_ADMIN_EMAIL" "$MGMT_ADMIN_PW" "admin"
	MGMT_ADMIN_DN="$ATTR_DN"
	record "Created: $MGMT_ADMIN_EMAIL at $MGMT_ADMIN_DN"	
}

mgmt_end() {
	# Clean up after mgmt_start
	delete_user "$MGMT_ADMIN_EMAIL"
}


mgmt_rest() {
	# Issue a REST call to the management subsystem
	local verb="$1" # eg "POST"
	local uri="$2"  # eg "/mail/users/add"
	shift; shift;   # remaining arguments are data

	# call function from lib/rest.sh
	rest_urlencoded "$verb" "$uri" "${MGMT_ADMIN_EMAIL}" "${MGMT_ADMIN_PW}" "$@" >>$TEST_OF 2>&1
	return $?
}

mgmt_rest_as_user() {
	# Issue a REST call to the management subsystem
	local verb="$1" # eg "POST"
	local uri="$2"  # eg "/mail/users/add"
	local email="$3"  # eg "alice@somedomain.com"
	local pw="$4"   # user's password
	shift; shift; shift; shift   # remaining arguments are data

	# call function from lib/rest.sh
	rest_urlencoded "$verb" "$uri" "${email}" "${pw}" "$@" >>$TEST_OF 2>&1
	return $?
}



mgmt_create_user() {
	local email="$1"
	local pass="${2:-$email}"
	local delete_first="${3:-yes}"
	local rc=0

	# ensure the user is deleted (clean test run)
	if [ "$delete_first" == "yes" ]; then
		delete_user "$email"
	fi
	record "[create user $email]"
	mgmt_rest POST /admin/mail/users/add "email=$email" "password=$pass"
	rc=$?
	return $rc
}

mgmt_assert_create_user() {
	local email="$1"
	local pass="$2"
	local delete_first="${3}"
	if ! mgmt_create_user "$email" "$pass" "$delete_first"; then
		test_failure "Unable to create user $email"
		test_failure "${REST_ERROR}"
		return 1
	fi
	return 0
}

mgmt_delete_user() {
	local email="$1"
	record "[delete user $email]"
	mgmt_rest POST /admin/mail/users/remove "email=$email"
	return $?
}

mgmt_assert_delete_user() {
	local email="$1"
	if ! mgmt_delete_user "$email"; then
		test_failure "Unable to cleanup/delete user $email"
		test_failure "$REST_ERROR"
		return 1
	fi
	return 0
}

mgmt_create_alias_group() {
	local alias="$1"
	shift
	record "[Create new alias group $alias]"
	record "members: $@"
	# ensure the group is deleted (clean test run)
	record "Try deleting any existing entry"
	if ! mgmt_rest POST /admin/mail/aliases/remove "address=$alias"; then
		get_attribute "$LDAP_ALIASES_BASE" "mail=$alias" "dn"
		if [ ! -z "$ATTR_DN" ]; then
			delete_dn "$ATTR_DN"
		fi
	fi

	record "Create the alias group"
	local members="$1" member
	shift
	for member;	do members="${members},${member}"; done

	mgmt_rest POST /admin/mail/aliases/add "address=$alias" "forwards_to=$members"
	return $?
}

mgmt_assert_create_alias_group() {
	local alias="$1"
	shift
	if ! mgmt_create_alias_group "$alias" "$@"; then
		test_failure "Unable to create alias group $alias"
		test_failure "${REST_ERROR}"
		return 1
	fi
	return 0
}

mgmt_delete_alias_group() {
	local alias="$1"
	record "[Delete alias group $alias]"
	mgmt_rest POST /admin/mail/aliases/remove "address=$alias"
	return $?
}

mgmt_assert_delete_alias_group() {
	local alias="$1"
	if ! mgmt_delete_alias_group "$alias"; then
		test_failure "Unable to cleanup/delete alias group $alias"
		test_failure "$REST_ERROR"
		return 1
	fi
	return 0
}


mgmt_privileges_add() {
	local user="$1"
	local priv="$2"  # only one privilege allowed
	record "[add privilege '$priv' to $user]"
	mgmt_rest POST "/admin/mail/users/privileges/add" "email=$user" "privilege=$priv"
	rc=$?
	return $rc
}

mgmt_assert_privileges_add() {
	if ! mgmt_privileges_add "$@"; then
		test_failure "Unable to add privilege '$2' to $1"
		test_failure "${REST_ERROR}"
		return 1
	fi
	return 0
}

mgmt_get_totp_token() {
	local secret="$1"
	local mru_token="$2"
	
	TOTP_TOKEN="" # this is set to the acquired token on success

	# the user would normally give the secret to an authenticator app
	# and get a token -- we'll do that out-of-band.  we have to run
	# the admin's python because setup does not do a 'pip install
	# pyotp', so the system python3 probably won't have it

	record "[Get the current token for the secret '$secret']"

	local count=0
	
	while [ -z "$TOTP_TOKEN" -a $count -lt 10 ]; do
		TOTP_TOKEN="$(/usr/local/lib/mailinabox/env/bin/python -c "import pyotp; totp=pyotp.TOTP(r'$secret'); print(totp.now());" 2>>"$TEST_OF")"
		if [ $? -ne 0 ]; then
			record "Failed: Could not generate a TOTP token !"
			return 1
		fi

		if [ "$TOTP_TOKEN" == "$mru_token" ]; then
			TOTP_TOKEN=""
			record "Waiting for unique token!"
			sleep 5
		else
			record "Success: token is '$TOTP_TOKEN'"
			return 0
		fi
		
		let count+=1
	done

	record "Failed: timeout !"
	TOTP_TOKEN=""
	return 1	
}


mgmt_totp_enable() {
	# enable TOTP for user specified
	#   returns 0 if successful and TOTP_SECRET will contain the secret and TOTP_TOKEN will contain the token used
	#   returns 1 if a REST error occured. $REST_ERROR has the message
	#   returns 2 if some other error occured
	#
	
	local user="$1"
	local pw="$2"
	TOTP_SECRET=""

	record "[Enable TOTP for $user]"

	# 1. get a totp secret
	if ! mgmt_rest_as_user "GET" "/admin/mfa/status" "$user" "$pw"; then
		REST_ERROR="Failed: GET/admin/mfa/status: $REST_ERROR"
		return 1
	fi
	
	TOTP_SECRET="$(/usr/bin/jq -r ".totp_secret" <<<"$REST_OUTPUT")"
	if [ $? -ne 0 ]; then
		record "Unable to obtain setup totp secret - is 'jq' installed?"
		return 2
	fi

	if [ "$TOTP_SECRET" == "null" ]; then
		record "No 'totp_secret' in the returned json !"
		return 2
	else
		record "Found TOTP secret '$TOTP_SECRET'"
	fi
	
	if ! mgmt_get_totp_token "$TOTP_SECRET"; then
		return 2
	fi
	
	# 3. enable TOTP
	record "Enabling TOTP using the secret and token"
	if ! mgmt_rest_as_user "POST" "/admin/mfa/totp/enable" "$user" "$pw" "secret=$TOTP_SECRET" "token=$TOTP_TOKEN"; then
		REST_ERROR="Failed: POST /admin/mfa/totp/enable: ${REST_ERROR}"
		return 1
	else
		record "Success: POST /mfa/totp/enable: '$REST_OUTPUT'"
	fi
		
	return 0
}


mgmt_assert_totp_enable() {
	local user="$1"
	mgmt_totp_enable "$@"
	local code=$?
	if [ $code -ne 0 ]; then
		test_failure "Unable to enable TOTP for $user"
		if [ $code -eq 1 ]; then
			test_failure "${REST_ERROR}"
		fi
		return 1
	fi
	get_attribute "$LDAP_USERS_BASE" "(&(mail=$user)(objectClass=totpUser))" "dn"
	if [ -z "$ATTR_DN" ]; then
		test_failure "totpUser objectClass not present on $user"
	fi
	record_search "(mail=$user)"
	return 0
}


mgmt_totp_disable() {
	local user="$1"
	local pw="$2"
	record "[Disable TOTP for $user]"
	if ! mgmt_rest_as_user "POST" "/admin/mfa/totp/disable" "$user" "$pw"
	then
		REST_ERROR="Failed: POST /admin/mfa/totp/disable: $REST_ERROR"
		return 1
	else
		record "Success"
		return 0
	fi
}

mgmt_assert_totp_disable() {
	local user="$1"
	mgmt_totp_disable "$@"
	local code=$?
	if [ $code -ne 0 ]; then
		test_failure "Unable to disable TOTP for $user: $REST_ERROR"
		return 1
	fi
	get_attribute "$LDAP_USERS_BASE" "(&(mail=$user)(objectClass=totpUser))" "dn"
	if [ ! -z "$ATTR_DN" ]; then
		test_failure "totpUser objectClass still present on $user"
	fi
	record_search "(mail=$user)"
	return 0
}

mgmt_assert_admin_me() {
	local user="$1"
	local pw="$2"
	local expected_status="${3:-ok}"
	shift; shift; shift;  # remaining arguments are data

	# note: GET /admin/me always returns http status 200, but errors are in
	# the json payload
	record "[Get /admin/me as $user]"
	if ! mgmt_rest_as_user "GET" "/admin/me" "$user" "$pw" "$@"; then
		test_failure "GET /admin/me as $user failed: $REST_ERROR"
		return 1

	else
		local status code
		status="$(/usr/bin/jq -r '.status' <<<"$REST_OUTPUT")"
		code=$?
		if [ $code -ne 0 ]; then
			test_failure "Unable to run jq ($code) on /admin/me json"
			return 1
				
		elif [ "$status" == "null" ]; then
			test_failure "No 'status' in /admin/me json"
			return 1

		elif [ "$status" != "$expected_status" ]; then
			test_failure "Expected a login status of '$expected_status', but got '$status'"
			return 1
			
		fi
	fi
	return 0
}
