#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####

#
# requires:
#    lib scripts: [ misc.sh ]
#    system-setup scripts: [ setup-defaults.sh ]
#

TEST_USER="totp_admin@$(email_domainpart "$EMAIL_ADDR")"
TEST_USER_PASS="$(static_qa_password)"
TEST_USER_TOTP_SECRET="6VXVWOSCY7JLU4VBZ6LQEJSBN6WYWECU"
TEST_USER_TOTP_LABEL="my phone"
