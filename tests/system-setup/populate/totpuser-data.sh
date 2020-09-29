#
# requires:
#    lib scripts: [ misc.sh ]
#    system-setup scripts: [ setup-defaults.sh ]
#

TEST_USER="totp_admin@$(email_domainpart "$EMAIL_ADDR")"
TEST_USER_PASS="$(static_qa_password)"
TEST_USER_TOTP_SECRET="6VXVWOSCY7JLU4VBZ6LQEJSBN6WYWECU"
TEST_USER_TOTP_LABEL="my phone"
