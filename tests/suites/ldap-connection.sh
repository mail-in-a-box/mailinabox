# -*- indent-tabs-mode: t; tab-width: 4; -*-

exe_test() {
	# run an executable and assert success or failure
	# argument 1 must be:
	#    "ZERO_RC" to assert the return code was 0
	#    "NONZERO_RC" to assert the return code was not 0
	# argument 2 is a description of the test for logging
	# argument 3 and higher are the executable and arguments
	local result_type=$1
	shift
	local desc="$1"
	shift
	test_start "$desc"
	record "[CMD: $@]"
	"$@" >>"$TEST_OF" 2>&1
	local code=$?
	case $result_type in
		ZERO_RC)
			if [ $code -ne 0 ]; then
				test_failure "expected zero return code, got $code"
			else
				test_success
			fi
			;;

		NONZERO_RC)
			if [ $code -eq 0 ]; then
				test_failure "expected non-zero return code"
			else
				test_success
			fi
			;;

		*)
			test_failure "unknown TEST type '$result_type'"
			;;
	esac
	test_end
}


tests() {
	# TLS: auth search to (local)host - expect success
	exe_test ZERO_RC "TLS-auth-host" \
			 ldapsearch -d 1 -b "dc=mailinabox" -H ldaps://$PRIMARY_HOSTNAME/ -x -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD"

	# TLS: auth search to localhost - expect failure ("hostname does not match CN in peer certificate")
	exe_test NONZERO_RC "TLS-auth-local" \
			 ldapsearch -d 1 -b "dc=mailinabox" -H ldaps://127.0.0.1/ -x -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD"

	# TLS: anon search - expect failure (anon bind disallowed)
	exe_test NONZERO_RC "TLS-anon-host" \
			 ldapsearch -d 1 -b "dc=mailinabox" -H ldaps://$PRIMARY_HOSTNAME/ -x
	
	# CLEAR: auth search to host - expected failure (not listening there)
	exe_test NONZERO_RC "CLEAR-auth-host" \
			 ldapsearch -d 1 -b "dc=mailinabox" -H ldap://$PRIVATE_IP/ -x -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD"

	# CLEAR: auth search to localhost - expect success
	exe_test ZERO_RC "CLEAR-auth-local" \
			 ldapsearch -d 1 -b "dc=mailinabox" -H ldap://127.0.0.1/ -x -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD"

	# CLEAR: anon search - expect failure (anon bind disallowed)
	exe_test NONZERO_RC "CLEAR-anon-local" \
			 ldapsearch -d 1 -b "dc=mailinabox" -H ldap://127.0.0.1/ -x
	
	# STARTTLS: auth search to localhost - expected failure ("hostname does not match CN in peer certificate")
	exe_test NONZERO_RC "STARTTLS-auth-local" \
			 ldapsearch -d 1 -b "dc=mailinabox" -H ldap://127.0.0.1/ -x -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" -ZZ

	# STARTTLS: auth search to host - expected failure (not listening there)
	exe_test NONZERO_RC "STARTTLS-auth-host" \
			 ldapsearch -d 1 -b "dc=mailinabox" -H ldap://$PRIVATE_IP/ -x -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" -ZZ

}


test_fail2ban() {
	test_start "fail2ban"
	
	# reset fail2ban
	record "[reset fail2ban]"
	fail2ban-client unban --all >>$TEST_OF 2>&1 ||
		test_failure "Unable to execute unban --all"

	# create regular user with password "alice"
	local alice="alice@somedomain.com"	  
	create_user "$alice" "alice"
	local alice_dn="$ATTR_DN"

	# log in a bunch of times with wrong password
	local n=0
	local total=25
	local banned=no
	record '[log in 25 times with wrong password]'
	while ! have_test_failures && [ $n -lt $total ]; do
		ldapsearch -H $LDAP_URL -D "$alice_dn" -w "bad-alice" -b "$LDAP_USERS_BASE" -s base "(objectClass=*)" 1>>$TEST_OF 2>&1
		local code=$?
		record "TRY $n: result code $code"
		
		if [ $code -eq 255 -a $n -gt 5 ]; then
			# banned - could not connect
			banned=yes
			break
			
		elif [ $code -ne 49 ]; then
			test_failure "Expected error code 49 (invalidCredentials), but got $code"
			continue
		fi
		
		let n+=1
		if [ $n -lt $total ]; then
			record "sleep 1"
			sleep 1
		fi
	done

	if ! have_test_failures && [ "$banned" == "no" ]; then
		# wait for fail2ban to ban
		record "[waiting for fail2ban]"
		record "sleep 5"
		sleep 5
		ldapsearch -H ldap://$PRIVATE_IP -D "$alice_dn" -w "bad-alice" -b "$LDAP_USERS_BASE" -s base "(objectClass=*)" 1>>$TEST_OF 2>&1
		local code=$?
		record "$n result: $code"
		if [ $code -ne 255 ]; then
			test_failure "Expected to be banned after repeated login failures, but wasn't"
		fi
	fi

	# delete alice
	delete_user "$alice"
	
	# reset fail2ban
	record "[reset fail2ban]"
	fail2ban-client unban --all >>$TEST_OF 2>&1 ||
		test_failure "Unable to execute unban --all"

	# done
	test_end
}


suite_start "ldap-connection"

tests
test_fail2ban

suite_end

