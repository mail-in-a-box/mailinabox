# -*- indent-tabs-mode: t; tab-width: 4; -*-
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####

#	
# Ensure dns is functional


assert_nslookup() {
    local query="$1"
    local nameserver="$2"
	local expected_ip="$3"
    record "[lookup $query]"
    local output code
    output=$(nslookup "$query" - "$nameserver" 2>&1)
    code=$?
    record "$output"
    if [ $code -ne 0 ]; then
        local msg="$(grep "^*" <<<"$output")"
        test_failure "Could not lookup $query on $nameserver - ${msg:-$output}"
		
	elif [ ! -z "$expected_ip" ]; then
		local addresses
		addresses=( $(awk '/Address:/ { print $2 }' <<<"$output") ) 
		if ! array_contains "$expected_ip" ${addresses[@]}; then
			test_failure "Expected $query to resolve to '$expected_ip' but got: ${addresses[*]}"
		fi
    fi
    
}

is_nsd_domain() {
	[ ! -e /etc/nsd/nsd.conf.d/zones.conf ] && return 1
 	grep -F "name: ${1:-xxxxx}" /etc/nsd/nsd.conf.d/zones.conf >/dev/null
}


test_nsd_queries() {
	test_start "nsd-queries"

	# lookup our own hostname
    assert_nslookup "$PRIMARY_HOSTNAME" "$PRIVATE_IP" "$PUBLIC_IP"
	
	# create a new domain and ensure we can look that up
	# 1. create a standard user alice with a new unique domain
	local alice="alice@alice.com"
	local alice_domain="$(email_domainpart "$alice")"

 	if is_nsd_domain "$alice_domain"; then
		test_failure "Before test start, $alice_domain should not be listed as an existing zone in /etc/nsd/nsd.conf.d/zones.conf"

	elif domain_exists "$alice_domain"; then
		test_failure "Before test start, $alice_domain should not be an existing MiaB domain"
		
	elif mgmt_assert_create_user "$alice" "alice_1234"; then
		# 2. assert we can lookup the new domain
		assert_nslookup "$alice_domain" "$PRIVATE_IP" "$PUBLIC_IP"
	
		# cleanup
		mgmt_assert_delete_user "$alice"

		if is_nsd_domain "$alice_domain"; then
			test_failure "Domain $alice_domain should not exist as a nsd domain in /etc/nsd/nsd.conf.d/zones.conf"
		fi
	fi
	
    test_end
}

test_bind_queries() {
	test_start "bind-queries"
    assert_nslookup "google.com" "localhost"
    test_end
}



suite_start "dns-basic" mgmt_start

test_nsd_queries
test_bind_queries

suite_end mgmt_end
