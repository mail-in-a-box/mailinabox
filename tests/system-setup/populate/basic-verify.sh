#!/bin/bash

. "$(dirname "$0")/../setup-defaults.sh" || exit 1
. "$(dirname "$0")/../../lib/all.sh" "$(dirname "$0")/../../lib" || exit 1
. "$(dirname "$0")/basic-data.sh" || exit 1
. /etc/mailinabox.conf || exit 1


# 1. the test user can still log in and send mail

echo "[User can still log in with their old passwords and send mail]" 1>&2
echo "python3 test_mail.py $PRIVATE_IP $TEST_USER $TEST_USER_PASS" 1>&2
python3 test_mail.py "$PRIVATE_IP" "$TEST_USER" "$TEST_USER_PASS" 1>&2
if [ $? -ne 0 ]; then
    echo "Basic mail functionality test failed"
    exit 1
fi


# 2. the test user's contact is still accessible in Roundcube

echo "[Force Roundcube contact sync]" 1>&2
# if MiaB's Nextcloud carddav configuration was removed all the
# contacts for it will be removed in the Roundcube database after the
# sync

roundcube_force_carddav_refresh "$TEST_USER" "$TEST_USER_PASS" 1>&2
rc=$?
if [ $rc -ne 0 ]
then
    echo "Roundcube <-> Nextcloud contact sync failed ($rc)"
    exit 1
fi

echo "[Ensure old Nextcloud contacts are still present]" 1>&2
echo "sqlite3 $STORAGE_ROOT/mail/roundcube/roundcube.sqlite \"select email from carddav_contacts where cuid='$TEST_USER_CONTACT_UUID'\"" 1>&2
output=$(sqlite3 "$STORAGE_ROOT/mail/roundcube/roundcube.sqlite" "select email from carddav_contacts where cuid='$TEST_USER_CONTACT_UUID'")
rc=$?
if [ $rc -ne 0 ]
then
    echo "Querying Roundcube's sqlite database failed ($rc)"
    exit 1
else
    echo "Success, found $output" 1>&2
fi

if [ "$output" != "$TEST_USER_CONTACT_EMAIL" ]
then
    echo "Unexpected email for contact uuid: got '$output', expected '$TEST_USER_CONTACT_EMAIL'"
    exit 1
fi

echo "OK basic-verify passed"
exit 0

