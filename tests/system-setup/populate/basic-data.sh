#
# requires:
#    lib scripts: [ misc.sh ]
#    system-setup scripts: [ setup-defaults.sh ]
#

TEST_USER="anna@$(email_domainpart "$EMAIL_ADDR")"
TEST_USER_PASS="$(static_qa_password)"
TEST_USER_CONTACT_UUID="e0642b47-9104-4adb-adfd-5f907d04216a"
TEST_USER_CONTACT_EMAIL="sam@bff.org"
