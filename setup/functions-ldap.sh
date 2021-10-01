# -*- indent-tabs-mode: t; tab-width: 4; -*-
#
# some helpful ldap function that are shared between setup/ldap.sh and
# test suites in tests/suites/*
#
get_attribute_from_ldif() {
	local attr="$1"
	local ldif="$2"
	# Gather values - handle multivalued attributes and values that
	# contain whitespace
	ATTR_DN="$(awk "/^dn:/ { print substr(\$0, 4); exit }" <<< $ldif)"
	ATTR_VALUE=()
	local line
	while read line; do
		[ -z "$line" ] && break
		local v=$(awk "/^$attr: / { print substr(\$0, length(\"$attr\")+3) }" <<<"$line")
		if [ ! -z "$v" ]; then
			ATTR_VALUE+=( "$v" )
		else
			v=$(awk "/^$attr:: / { print substr(\$0, length(\"$attr\")+4) }" <<<"$line")
			[ ! -z "$v" ] && ATTR_VALUE+=( $(base64 --decode --wrap=0 <<<"$v") )
		fi
	done <<< "$ldif"
	return 0
}

get_attribute() {
	# Returns first matching dn in $ATTR_DN (empty if not found),
	# along with associated values of the specified attribute in
	# $ATTR_VALUE as an array
	local base="$1"
	local filter="$2"
	local attr="$3"
	local scope="${4:-sub}"
	local bind_dn="${5:-}"
	local bind_pw="${6:-}"
	local stderr_file="/tmp/ldap_search.$$.err"
	local code_file="$stderr_file.code"

	# Issue the search
	local args=( "-Q" "-Y" "EXTERNAL" "-H" "ldapi:///" )
	if [ ! -z "$bind_dn" ]; then
		args=("-H" "$LDAP_URL" "-x" "-D" "$bind_dn" "-w" "$bind_pw" )
	fi
	args+=( "-LLL" "-s" "$scope" "-o" "ldif-wrap=no" "-b" "$base" )

	local result
	result=$(ldapsearch ${args[@]} "$filter" "$attr" 2>$stderr_file; echo $? >$code_file)
	local exitcode=$(cat $code_file)
	local stderr=$(cat $stderr_file)
	rm -f "$stderr_file"
	rm -f "$code_file"
	if [ $exitcode -ne 0 -a $exitcode -ne 32 ]; then
		# 255 == unable to contact server
		# 32 == No such object
		die "$stderr"
	fi

	get_attribute_from_ldif "$attr" "$result"
}


slappasswd_hash() {
	# hash the given password with our preferred algorithm and in a
	# format suitable for ldap. see crypt(3) for format
	slappasswd -h {CRYPT} -c \$6\$%.16s -s "$1"
}

debug_search() {
	# perform a search and output the results
	# arg 1: the search criteria
	# arg 2: [optional] the base rdn
	# arg 3-: [optional] attributes to output, if not specified
	#        all are output
	local base="$LDAP_BASE"
	local query="(objectClass=*)"
	local scope="sub"
	local attrs=( )
	case "$1" in
		\(* )
			# filters start with an open paren...
			query="$1"
			;;
		*@* )
			# looks like an email address
			query="(|(mail=$1)(maildrop=$1))"
			;;
		* )
			# default: it's a dn
			base="$1"
			;;
	esac
	shift
	
	if [ $# -gt 0 ]; then
		base="$1"
		shift
	fi

	if [ $# -gt 0 ]; then
		attrs=( $@ )
	fi

	local ldif=$(ldapsearch -H $LDAP_URL -o ldif-wrap=no -b "$base" -s $scope -LLL -x -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" "$query" ${attrs[@]}; exit 0)

	# expand 'member'
	local line
	while read line; do
		case "$line" in
			member:* )
				local member_dn=$(cut -c9- <<<"$line")
				get_attribute "$member_dn" "objectClass=*" mail base "$LDAP_ADMIN_DN" "$LDAP_ADMIN_PASSWORD"
				if [ -z "$ATTR_DN" ]; then
					echo "$line"
					echo "#^ member DOES NOT EXIST"
				else
					echo "member: ${ATTR_VALUE[@]}"
					echo "#^ $member_dn"
				fi
				;;
			* )
				echo "$line"
				;;
		esac
	done <<<"$ldif"
}
