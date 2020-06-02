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

	local auth_user="${MGMT_ADMIN_EMAIL}"
	local auth_pass="${MGMT_ADMIN_PW}"
	local url="https://$PRIMARY_HOSTNAME${uri}"
	local data=()
	local item output
	
	for item; do data+=("--data-urlencode" "$item"); done

	record "spawn: curl -w \"%{http_code}\" -X $verb --user \"${auth_user}:xxx\" ${data[@]} $url"
	output=$(curl -s -S -w "%{http_code}" -X $verb --user "${auth_user}:${auth_pass}" "${data[@]}" $url 2>>$TEST_OF)
	local code=$?

	# http status is last 3 characters of output, extract it
	REST_HTTP_CODE=$(awk '{S=substr($0,length($0)-2)} END {print S}' <<<"$output")
	REST_OUTPUT=$(awk 'BEGIN{L=""}{ if(L!="") print L; L=$0 } END { print substr(L,1,length(L)-3) }' <<<"$output")
	REST_ERROR=""
	[ -z "$REST_HTTP_CODE" ] && REST_HTTP_CODE="000"

	if [ $code -ne 0 ]; then
		if [ $code -ne 16 -o $REST_HTTP_CODE -ne 200 ]; then
			REST_ERROR="CURL failed with code $code"
			record "${F_DANGER}$REST_ERROR${F_RESET}"
			record "$output"
			return 1
		fi
	fi
	if [ $REST_HTTP_CODE -lt 200 -o $REST_HTTP_CODE -ge 300 ]; then
		REST_ERROR="REST status $REST_HTTP_CODE: $REST_OUTPUT"
		record "${F_DANGER}$REST_ERROR${F_RESET}"
		return 2
	fi
	record "CURL succeded, HTTP status $REST_HTTP_CODE"
	record "$output"
	return 0	
}

systemctl_reset() {
	local service="$1"
	# for travis-ci: reset nsd to avoid "nsd.service: Start request
	# repeated too quickly", which occurs inside kick() of the
	# management flask app when "system restart nsd" is called on
	# detection of a new mail domain
	record "[systemctl reset-failed $service]"
	systemctl reset-failed $service 2>&1 >>$TEST_OF
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
