#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####


test_password_change() {
    # ensure user passwords can be changed from roundcube
    test_start "password-change"

    # create regular user alice
    local alice="alice@somedomain.com"
    local alice_old_pw="alice_1234"
    local alice_new_pw="123_new_alice"
    create_user "$alice" "$alice_old_pw"

    # change the password using roundcube's ui
    assert_browser_test \
        roundcube/change_pw.py \
        "$alice" \
        "$alice_old_pw" \
        "$alice_new_pw"

    # test login using new password
    if ! have_test_failures; then
        get_attribute "$LDAP_USERS_BASE" "mail=$alice" "dn"
        assert_r_access "$ATTR_DN" "$ATTR_DN" "$alice_new_pw" read mail
    fi
    
    # clean up
    delete_user "$alice"
    test_end
}


test_create_contact() {
    #
    # ensure contacts can be created in Roundcube and that those
    # contacts appears in Nextcloud (support both local and remote
    # Nextcloud setups)
    #
    # we're not going to check that a contact created in Nextcloud is
    # available in Roundcube because there's already a test for that
    # in the suite remote-nextcloud.sh
    #
    test_start "create-contact"

    # create regular user alice
    local alice="alice@somedomain.com"
    local alice_pw="$(generate_password 16)"
    create_user "$alice" "$alice_pw"

    # which address book in roundcube?
    # .. local nextcloud: the name is "ownCloud (Contacts)
    # .. remote nextcloud: the name is the remote server name
    #
    # RCM_PLUGIN_DIR is defined in lib/locations.sh    
    record "[get address book name]"
    local code address_book
    address_book=$(php${PHP_VER} -r "require '$RCM_PLUGIN_DIR/carddav/config.inc.php'; isset(\$prefs['cloud']) ? print \$prefs['cloud']['name'] : print \$prefs['ownCloud']['name'];" 2>>$TEST_OF)
    record "name: $address_book"
    code=$?
    if [ $code -ne 0 ]; then
        test_failure "Could not determine the address book name to use"

    else
        # generate an email address - the contact's email must be
        # unique or it can't be created
        local contact_email="bob_bacon$(generate_uuid | awk -F- '{print $1 }')@example.com"
        
        # create a contact using roundcube's ui
        record "[create contact in Roundcube]"
        if assert_browser_test \
               roundcube/create_contact.py \
               "$alice" \
               "$alice_pw" \
               "$address_book" \
               "Bob" \
               "Bacon" \
               "$contact_email"
        then
            # ensure the contact exists in Nextcloud.
            #
            # skip explicitly checking for existance - when we delete
            # the contact we're also checking that it exists (delete
            # will fail otherwise)
            
            # record "[ensure contact exists in Nextcloud]"
            # assert_browser_test \
            #     nextcloud/contacts.py \
            #     "exists" \
            #     "$alice" \
            #     "$alice_pw" \
            #     "Bob" \
            #     "Bacon" \
            #     "$contact_email"

            # delete the contact
            record "[delete the contact in Nextcloud]"
            assert_browser_test \
                nextcloud/contacts.py \
                "delete" \
                "$alice" \
                "$alice_pw" \
                "Bob" \
                "Bacon" \
                "$contact_email"
        fi
    fi
    
    test_end
    
}



suite_start "roundcube"

test_password_change
test_create_contact

suite_end
