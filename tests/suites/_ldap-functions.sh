# -*- indent-tabs-mode: t; tab-width: 4; -*-

generate_uuid() {
	local uuid
	uuid=$(python3 -c "import uuid; print(uuid.uuid4())")
	[ $? -ne 0 ] && die "Unable to generate a uuid"
	echo "$uuid"
}

sha1() {
	local txt="$1"
	python3 -c "import hashlib; m=hashlib.sha1(); m.update(bytearray(r'''$txt''','utf-8')); print(m.hexdigest());" || die "Unable to generate sha1 hash"
}

delete_user() {
	local email="$1"
	local domainpart="$(awk -F@ '{print $2}' <<< "$email")"
	get_attribute "$LDAP_USERS_BASE" "mail=$email" "dn"
	[ -z "$ATTR_DN" ] && return 0
	record "[delete user $email]"
	ldapdelete -H $LDAP_URL -x -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" "$ATTR_DN" >>$TEST_OF 2>&1 || die "Unable to delete user $ATTR_DN (as admin)"
	record "deleted"
	# delete the domain if there are no more users in the domain
	get_attribute "$LDAP_USERS_BASE" "mail=*@${domainpart}" "dn"
	[ ! -z "$ATTR_DN" ] && return 0
	get_attribute "$LDAP_DOMAINS_BASE" "dc=${domainpart}" "dn"
	if [ ! -z "$ATTR_DN" ]; then
		record "[delete domain $domainpart]"
		ldapdelete -H $LDAP_URL -x -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" "$ATTR_DN" >>$TEST_OF 2>&1 || die "Unable to delete domain $ATTR_DN (as admin)"
		record "deleted"
	fi
}

create_user() { 
	local email="$1"
	local pass="${2:-$email}"
	local priv="${3:-test}"
	local localpart="$(awk -F@ '{print $1}' <<< "$email")"
	local domainpart="$(awk -F@ '{print $2}' <<< "$email")"
	#local uid="$localpart"
	local uid="$(sha1 "$email")"
	local dn="uid=${uid},${LDAP_USERS_BASE}"
	
	delete_user "$email"

	record "[create user $email ($dn)]"
	delete_dn "$dn"
	
	ldapadd -H "$LDAP_URL" -x -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" >>$TEST_OF 2>&1 <<EOF
dn: $dn
objectClass: inetOrgPerson
objectClass: mailUser
objectClass: shadowAccount
uid: $uid
cn: $localpart
sn: $localpart
displayName: $localpart
mail: $email
maildrop: $email
mailaccess: $priv
userPassword: $(slappasswd_hash "$pass")
EOF
	[ $? -ne 0 ] && die "Unable to add user $dn (as admin)"

	# create domain entry, if needed
	get_attribute "$LDAP_DOMAINS_BASE" "dc=${domainpart}" dn
	if [ -z "$ATTR_DN" ]; then
		record "[create domain entry $domainpart]"
		ldapadd -H $LDAP_URL -x -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" >>$TEST_OF 2>&1 <<EOF
dn: dc=${domainpart},$LDAP_DOMAINS_BASE
objectClass: domain
dc: ${domainpart}
businessCategory: mail
EOF
		[ $? -ne 0 ] && die "Unable to add domain ${domainpart} (as admin)"
	fi
	
	ATTR_DN="$dn"
}


delete_dn() {
	local dn="$1"
	get_attribute "$dn" "objectClass=*" "dn" base
	[ -z "$ATTR_DN" ] && return 0
	record "delete dn: $dn"
	ldapdelete -H $LDAP_URL -x -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" "$dn" >>$TEST_OF 2>&1 || die "Unable to delete $dn (as admin)"
}	 

create_service_account() {
	local cn="$1"
	local pass="${2:-$cn}"
	local dn="cn=${cn},${LDAP_SERVICES_BASE}"

	record "[create service account $cn]"
	delete_dn "$dn"
	
	ldapadd -H "$LDAP_URL" -x -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" >>$TEST_OF 2>&1 <<EOF
dn: $dn
objectClass: simpleSecurityObject
objectClass: organizationalRole
cn: $cn
description: TEST ${cn} service account
userPassword: $(slappasswd_hash "$pass")
EOF
	[ $? -ne 0 ] && die "Unable to add service account $dn (as admin)"
	ATTR_DN="$dn"
}

delete_service_account() {
	local cn="$1"
	local dn="cn=${cn},${LDAP_SERVICES_BASE}"
	record "[delete service account $cn]"
	delete_dn "$dn"
}

create_alias_group() {
	local alias="$1"
	shift
	record "[Create new alias group $alias]"
	# add alias group with dn's as members
	get_attribute "$LDAP_ALIASES_BASE" "mail=$alias" "dn"
	if [ ! -z "$ATTR_DN" ]; then
		delete_dn "$ATTR_DN"
	fi
	
	ATTR_DN="cn=$(generate_uuid),$LDAP_ALIASES_BASE"
	of="/tmp/create_alias.$$.ldif"
	cat >$of 2>>$TEST_OF <<EOF
dn: $ATTR_DN
objectClass: mailGroup
mail: $alias
EOF
	local member
	for member; do
		case $member in
			*@* )
				echo "rfc822MailMember: $member" >>$TEST_OF
				echo "rfc822MailMember: $member" >>$of 2>>$TEST_OF
				;;
			* )
				echo "member: $member" >>$TEST_OF
				echo "member: $member" >>$of 2>>$TEST_OF
				;;
		esac
	done
	ldapadd -H "$LDAP_URL" -x -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" -f $of >>$TEST_OF 2>&1 || die "Unable to add alias group $alias"
	rm -f $of
}

delete_alias_group() {
	record "[delete alias group $1]"
	get_attribute "$LDAP_ALIASES_BASE" "(mail=$1)" dn
	[ ! -z "$ATTR_DN" ] && delete_dn "$ATTR_DN"
}


add_alias() {
	local user_dn="$1"
	local alias="$2"
	local type="${3:-group}"
	if [ $type == user ]; then
		# add alias as additional 'mail' attribute to user's dn
		record "[Add alias $alias to $user_dn]"
		ldapmodify -H "$LDAP_URL" -x -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" >>$TEST_OF 2>&1 <<EOF
dn: $user_dn
add: mail
mail: $alias
EOF
		local r=$?
		[ $r -ne 0 ] && die "Unable to modify $user_dn"
		
	elif [ $type == group ]; then
		# add alias as additional 'member" to a mailGroup alias list
		record "[Add member $user_dn to alias $alias]"
		get_attribute "$LDAP_ALIASES_BASE" "mail=$alias" "dn"
		if [ -z "$ATTR_DN" ]; then
			# don't automatically add because it should be cleaned
			# up by the caller
			die "Alias grour $alias does not exist"
		else
			ldapmodify -H "$LDAP_URL" -x -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" >>$TEST_OF 2>&1 <<EOF
dn: $ATTR_DN
add: member
member: $user_dn
EOF
			local code=$?
			if [ $code -ne 20 -a $code -ne 0 ]; then
				# 20=Type or value exists
				die "Unable to add user $user_dn to alias $alias"
			fi
		fi
	else
		die "Invalid type '$type' to add_alias"
	fi

}


create_permitted_senders_group() {
	# add a permitted senders group. specify the email address that
	# the members may MAIL FROM as the first argument, followed by all
	# member dns. If the group already exists, it is deleted first.
	#
	# on return, the global variable ATTR_DN is set to the dn of the
	# created mailGroup
	local mail_from="$1"
	shift
	record "[create permitted sender list $mail_from]"
	get_attribute "$LDAP_PERMITTED_SENDERS_BASE" "(&(objectClass=mailGroup)(mail=$mail_from))" dn
	if [ ! -z "$ATTR_DN" ]; then
		delete_dn "$ATTR_DN"
	fi

	local tmp="/tmp/tests.$$.ldif"
	ATTR_DN="cn=$(generate_uuid),$LDAP_PERMITTED_SENDERS_BASE"
	cat >$tmp <<EOF
dn: $ATTR_DN
objectClass: mailGroup
mail: $mail_from
EOF
	local member
	for member; do
		echo "member: $member" >>$tmp
		echo "member: $member" >>$TEST_OF
	done
	
	ldapadd -H "$LDAP_URL" -x -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" -f $tmp >>$TEST_OF 2>&1
	local r=$?
	rm -f $tmp
	[ $r -ne 0 ] && die "Unable to add permitted senders group $mail_from"
}

delete_permitted_senders_group() {
	local mail_from="$1"
	record "[delete permitted sender list $mail_from]"
	get_attribute "$LDAP_PERMITTED_SENDERS_BASE" "(&(objectClass=mailGroup)(mail=$mail_from))" dn
	if [ ! -z "$ATTR_DN" ]; then
		delete_dn "$ATTR_DN"
	fi
}


test_r_access() {
	# tests read or unreadable access
	# sets global variable FAILURE on return
	local user_dn="$1"
	local login_dn="$2"
	local login_pass="$3"
	local access="${4:-no-read}"  # should be "no-read" or "read"
	shift; shift; shift; shift

	if ! array_contains $access read no-read; then
		die "Invalid parameter '$access' to function test_r_access"
	fi

	# get all attributes using login_dn's account
	local attr
	local search_output result=()
	record "[Get attributes of $user_dn by $login_dn]"
	search_output=$(ldapsearch -LLL -o ldif-wrap=no -H "$LDAP_URL" -b "$user_dn" -s base -x -D "$login_dn" -w "$login_pass" 2>>$TEST_OF)
	local code=$?
	# code 32: No such object (doesn't exist or login can't see it)
	[ $code -ne 0 -a $code -ne 32 ] && die "Unable to find entry $user_dn by $login_dn"
	while read attr; do
		record "line: $attr"
		attr=$(awk -F: '{print $1}' <<< "$attr")
		[ "$attr" != "dn" -a "$attr" != "objectClass" ] && result+=($attr)
	done <<< "$search_output"
	record "check for $access access to ${@:-ALL}"
	record "comparing to actual: ${result[@]}"

	
	local failure=""
	if [ $access == "no-read" -a $# -eq 0 ]; then
		# check that no attributes are readable
		if [ ${#result[*]} -gt 0 ]; then
			failure="Attributes '${result[*]}' of $user_dn should not be readable by $login_dn"
		fi
	else
		# check that specified attributes are/aren't readable
		for attr; do
			if [ $access == "no-read" ]; then
				if array_contains $attr ${result[@]}; then
					failure="Attribute $attr of $user_dn should not be readable by $login_dn"
					break
				fi
			else
				if ! array_contains $attr ${result[@]}; then
					failure="Attribute $attr of $user_dn should be readable by $login_dn got (${result[*]})"
					break
				fi
			fi
		done
	fi

	FAILURE="$failure"
}


assert_r_access() {
	# asserts read or unreadable access
	FAILURE=""
	test_r_access "$@"
	[ ! -z "$FAILURE" ] && test_failure "$FAILURE"
}


test_w_access() {
	# tests write or unwritable access
	# sets global variable FAILURE on return
	# if no attributes given, test user attributes
	#	uuid, cn, sn, mail, maildrop, mailaccess
	local user_dn="$1"
	local login_dn="$2"
	local login_pass="$3"
	local access="${4:-no-write}"  # should be "no-write" or "write"
	shift; shift; shift; shift
	local moddn=""
	local attrs=( $@ )
	
	if ! array_contains $access write no-write; then
		die "Invalid parameter '$access' to function test_w_access"
	fi

	if [ ${#attrs[*]} -eq 0 ]; then
		moddn=uid
		attrs=("cn=alice fiction" "sn=fiction" "mail" "maildrop" "mailaccess=admin")
	fi

	local failure=""
	
	# check that select attributes are not writable
	if [ ! -z "$moddn" ]; then
		record "[Change attribute ${moddn}]"
		delete_dn "${moddn}=some-uuid,$LDAP_USERS_BASE"
		ldapmodify -H "$LDAP_URL" -x -D "$login_dn" -w "$login_pass" >>$TEST_OF 2>&1 <<EOF
dn: $user_dn
changetype: moddn
newrdn: ${moddn}=some-uuid
deleteoldrdn: 1
EOF
		local r=$?
		if [ $r -eq 0 ]; then
			if [ "$access" == "no-write" ]; then
				failure="Attribute $moddn of $user_dn should not be changeable by $login_dn"
			fi
		elif [ $r -eq 50 ]; then
			if [ "$access" == "write" ]; then
				failure="Attribute $moddn of $user_dn should be changeable by $login_dn"
			fi
		else
			die "Error attempting moddn change of $moddn (code $?)"
		fi
	fi
	

	if [ -z "$failure" ]; then
		local attrvalue attr value
		for attrvalue in "${attrs[@]}"; do
			attr="$(awk -F= '{print $1}' <<< "$attrvalue")"
			value="$(awk -F= '{print substr($0,length($1)+2)}' <<< "$attrvalue")"
			[ -z "$value" ] && value="alice2@abc.com"
			record "[Change attribute $attr]"
			ldapmodify -H "$LDAP_URL" -x -D "$login_dn" -w "$login_pass" >>$TEST_OF 2>&1 <<EOF
dn: $user_dn
replace: $attr
$attr: $value
EOF
			r=$?
			if [ $r -eq 0 ]; then
				if [ $access == "no-write" ]; then
					failure="Attribute $attr of $user_dn should not be changeable by $login_dn"
					break
				fi
			elif [ $r -eq 50 ]; then
				if [ $access == "write" ]; then
					failure="Attribute $attr of $user_dn should be changeable by $login_dn"
					break
				fi
			else
				die "Error attempting change of $attr to '$value'"
			fi
		done
	fi

	FAILURE="$failure"
}

assert_w_access() {
	# asserts write or unwritable access
	FAILURE=""
	test_w_access "$@"
	[ ! -z "$FAILURE" ] && test_failure "$FAILURE"
}


test_search() {
	# test if access to search something is allowed
	# sets global variable SEARCH_DN_COUNT on return
	local base_dn="$1"
	local login_dn="$2"
	local login_pass="$3"
	local scope="${4:-sub}"
	local filter="$5"

	let SEARCH_DN_COUNT=0

	local line search_output
	record "[Perform $scope search of $base_dn by $login_dn]"
	search_output=$(ldapsearch -H $LDAP_URL -o ldif-wrap=no -b "$base_dn" -s "$scope" -LLL -x -D "$login_dn" -w "$login_pass" $filter 2>>$TEST_OF)
	local code=$?
	# code 32: No such object (doesn't exist or login can't see it)
	[ $code -ne 0 -a $code -ne 32 ] && die "Unable to search $base_dn by $login_dn"
	
	while read line; do
		record "line: $line"
		case $line in
			dn:*)
				let SEARCH_DN_COUNT+=1
				;;
		esac
	done <<< "$search_output"
	record "$SEARCH_DN_COUNT entries found"
}


record_search() {
	local dn="$1"
	record "[Contents of $dn]"
	debug_search "$dn" >>$TEST_OF 2>&1
	return 0
}
