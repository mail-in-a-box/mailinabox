# -*- indent-tabs-mode: t; tab-width: 4; -*-
#	
# Test the setup modification script setup/mods.available/remote-nextcloud.sh
# Prerequisites:
#
#    - Nextcloud is already installed and MiaB-LDAP is already
#      configured to use it.
#
#      ie. remote-nextcloud.sh was run on MiaB-LDAP by
#          setup/start.sh because there was a symbolic link from
#          local/remote-nextcloud.sh to the script in
#          mods.available
#
#    - The remote Nextcloud has been configured to use MiaB-LDAP
#      for users and groups.
#
#      ie. connect-nextcloud-to-miab.sh was copied to the remote Nextcloud
#      server and was run successfully there
#

is_configured() {
    . /etc/mailinabox_mods.conf
    if [ $? -ne 0 -o -z "$NC_HOST" ]; then
        return 1
    fi
    return 0
}

assert_is_configured() {
    if ! is_configured; then
        test_failure "remote-nextcloud is not configured"
        return 1
    fi
    return 0
}


assert_roundcube_carddav_contact_exists() {
    local user="$1"
    local pass="$2"
    local c_uid="$3"
    local output
    record "[checking that roundcube contact with vcard UID=$c_uid exists]"
	roundcube_carddav_contact_exists "$user" "$pass" "$c_uid" 2>>$TEST_OF
	local rc=$?
	
    if [ $rc -eq 0 ]; then
		return
	elif [ $rc -eq 1 ]; then
        test_failure "Contact not found in Roundcube"
        record "Not found"
        record "Existing entries:"
		roundcube_dump_contacts >>$TEST_OF 2>&1
	else
		test_failure "Error querying roundcube contacts"
		return
    fi
}


test_mail_from_nextcloud() {
    test_start "mail_from_nextcloud"
    test_end    
}

test_nextcloud_contacts() {
    test_start "nextcloud-contacts"

    if ! assert_is_configured; then
		test_end
		return
	fi

    local alice="alice.nc@somedomain.com"
    local alice_pw="$(generate_password 16)"

	# create local user alice
	mgmt_assert_create_user "$alice" "$alice_pw"


    #
    # 1. create contact in Nextcloud - ensure it is available in Roundcube
    #    
    # this will validate Nextcloud's ability to authenticate users via
    # LDAP and that Roundcube is able to reach Nextcloud for contacts
    #

	#record "[create address book 'contacts' for $alice]"
	#carddav_make_addressbook "$alice" "$alice_pw" "contacts" 2>>$TEST_OF

    # add new contact to alice's Nextcloud account using CardDAV API
    local c_uid="$(generate_uuid)"
    record "[add contact 'JimIno' to $alice]"
    if ! carddav_add_contact \
        "$alice" \
        "$alice_pw" \
        "JimIno" \
        "555-1212" \
        "jim@ino.com" \
        "$c_uid" \
		2>>$TEST_OF
	then
		test_failure "Could not add contact for $alice in Nextcloud: $REST_ERROR_BRIEF"
		test_end
		return
	fi
    
    # force a refresh/sync of the contacts in Roundcube
    record "[forcing refresh of roundcube contact for $alice]"
    roundcube_force_carddav_refresh "$alice" "$alice_pw" >>$TEST_OF 2>&1 || \
        test_failure "Could not refresh roundcube contacts for $alice"

    # query the roundcube sqlite database for the new contact
    assert_roundcube_carddav_contact_exists "$alice" "$alice_pw" "$c_uid"
    
    # delete the contact
    record "[delete contact with vcard uid '$c_uid' from $alice]"
    carddav_delete_contact "$alice" "$alice_pw" "$c_uid" 2>>$TEST_OF || \
        test_failure "Unable to delete contact for $alice in Nextcloud"
    

    #
    # 2. create contact in Roundcube - ensure contact appears in Nextcloud
    #
    # TODO

    
    # clean up
    mgmt_assert_delete_user "$alice"
    
    test_end
}


suite_start "remote-nextcloud" mgmt_start

#test_mail_from_nextcloud
test_nextcloud_contacts

suite_end mgmt_end




