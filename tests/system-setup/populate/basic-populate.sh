#!/bin/bash

. "$(dirname "$0")/../setup-defaults.sh" || exit 1
. "$(dirname "$0")/../../lib/all.sh" "$(dirname "$0")/../../lib" || exit 1
. "$(dirname "$0")/basic-data.sh" || exit 1


#
# Add user
#
if ! populate_miab_users "" "" "" "${TEST_USER}:${TEST_USER_PASS}"
then
    echo "Unable to add user"
    exit 1
fi

#
# Add Nextcloud contact and force Roundcube contact sync to ensure the
# roundcube carddav addressbooks and contacts tables are populated in
# case a remote nextcloud is subsequently configured and the
# syncronization disabled.
#
if ! carddav_ls "$TEST_USER" "$TEST_USER_PASS" --insecure 2>/dev/null
then
    echo "Could not enumerate contacts: $REST_ERROR"
    exit 1
fi
echo "Current contacts count: ${#FILES[@]}"
    
if array_contains "$TEST_USER_CONTACT_UUID.vcf" "${FILES[@]}"; then
    echo "Contact $TEST_USER_CONTACT_UUID already present"
else
    if ! carddav_add_contact "$TEST_USER" "$TEST_USER_PASS" "Anna" "666-1111" "$TEST_USER_CONTACT_EMAIL" "$TEST_USER_CONTACT_UUID" --insecure 2>/dev/null
    then
        echo "Could not add contact: $REST_ERROR"
        exit 1
    fi
    
    echo "Force Roundcube contact sync"
    if ! roundcube_force_carddav_refresh "$TEST_USER" "$TEST_USER_PASS"
    then
        echo "Roundcube <-> Nextcloud contact sync failed"
        exit 1
    fi
fi

exit 0

