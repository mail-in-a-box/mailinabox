#!/bin/bash

. "$(dirname "$0")/../setup-defaults.sh" || exit 1
. "$(dirname "$0")/../../lib/all.sh" "$(dirname "$0")/../../lib" || exit 1
. "$(dirname "$0")/totpuser-data.sh" || exit 1


url=""
admin_email="$EMAIL_ADDR"
admin_pass="$EMAIL_PW"


#
# Add user
#
if ! populate_miab_users "$url" "$admin_email" "$admin_pass" "${TEST_USER}:${TEST_USER_PASS}"
then
    echo "Unable to add user"
    exit 1
fi

# make the user an admin
if ! rest_urlencoded POST "${url%/}/admin/mail/users/privileges/add" "$admin_email" "$admin_pass" --insecure -- "email=$TEST_USER" "privilege=admin" 2>/dev/null
then
    echo "Unable to add 'admin' privilege. err=$REST_ERROR" 1>&2
    exit 1
fi

# enable totp
token="$(totp_current_token "$TEST_USER_TOTP_SECRET")"
if ! rest_urlencoded POST "${url%/}/admin/mfa/totp/enable" "$TEST_USER" "$TEST_USER_PASS" --insecure "secret=$TEST_USER_TOTP_SECRET" "token=$token" "label=$TEST_USER_TOTP_LABEL" 2>/dev/null; then
    echo "Unable to enable TOTP. err=$REST_ERROR" 1>&2
    exit 1
fi


exit 0

