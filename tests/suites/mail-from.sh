# -*- indent-tabs-mode: t; tab-width: 4; -*-
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####



test_permitted_sender_fail() {
	# a user may not send MAIL FROM someone else, when not permitted
	test_start "permitted-sender-fail"
	# create standard users alice, bob, and mary
	local alice="alice@somedomain.com"
	local bob="bob@anotherdomain.com"
	local mary="mary@anotherdomain.com"
	create_user "$alice" "alice"
	create_user "$bob" "bob"
	create_user "$mary" "mary"

	# login as mary, send from bob, to alice
	start_log_capture
	record "[Mailing to alice from bob as mary]"
	local output
	output="$($PYMAIL -f $bob -to $alice alice $PRIVATE_IP $mary mary 2>&1)"
	if ! assert_python_failure $? "$output" SMTPRecipientsRefused
	then
		# additional "color"
		test_failure "user should not be permitted to send as another user"
	fi

	# expect errors, so don't assert
	check_logs

	delete_user "$alice"
	delete_user "$bob"
	delete_user "$mary"
	test_end
}


test_permitted_sender_alias() {
	# a user may send MAIL FROM one of their own aliases
	test_start "permitted-sender-alias"
	# create standard users alice and bob
	local alice="alice@somedomain.com"
	local bob="bob@anotherdomain.com"
	local mary="mary@anotherdomain.com"
	local jane="jane@google.com"
	create_user "$alice" "alice"
	create_user "$bob" "bob"
	local bob_dn="$ATTR_DN"

	# add mary as one of bob's aliases - to bob's 'mail' attribute
	add_alias $bob_dn $mary user

	# add jane as one of bob's aliases - to jane's alias group
	create_alias_group $jane $bob_dn

	# login as bob, send from mary, to alice
	start_log_capture
	record "[Mailing to alice from mary as bob]"
	local output
	output="$($PYMAIL -f $mary -to $alice alice $PRIVATE_IP $bob bob 2>&1)"
	if ! assert_python_success $? "$output"; then
		# additional "color"
		test_failure "bob should be permitted to MAIL FROM $mary, his own alias: $(python_error "$output")"
	fi

	assert_check_logs

	# login as bob, send from jane, to alice
	start_log_capture
	record "[Mailing to alice from jane as bob]"
	local output
	output="$($PYMAIL -f $jane -to $alice alice $PRIVATE_IP $bob bob 2>&1)"
	if ! assert_python_success $? "$output"; then
		# additional "color"
		test_failure "bob should be permitted to MAIL FROM $jane, his own alias: $(python_error "$output")"
	fi

	assert_check_logs

	delete_user "$alice"
	delete_user "$bob"
	delete_alias_group "$jane"
	test_end
}


test_permitted_sender_explicit() {
	# a user may send MAIL FROM an address that is explicitly allowed
	# by a permitted-senders group
	# a user may not send MAIL FROM an address that has a permitted
	# senders list which they are not a member, even if they are an
	# alias group member
	test_start "permitted-sender-explicit"

	# create standard users alice and bob
	local alice="alice@somedomain.com"
	local bob="bob@anotherdomain.com"
	create_user "$alice" "alice"
	local alice_dn="$ATTR_DN"
	create_user "$bob" "bob"
	local bob_dn="$ATTR_DN"

	# create an alias that forwards to bob and alice
	local alias="mary@anotherdomain.com"
	create_alias_group $alias $bob_dn $alice_dn
	
	# create a permitted-senders group with only alice in it
	create_permitted_senders_group $alias $alice_dn

	# login as alice, send from alias to bob
	start_log_capture
	record "[Mailing to bob from alice as alias/mary]"
	local output
	output="$($PYMAIL -f $alias -to $bob bob $PRIVATE_IP $alice alice 2>&1)"
	if ! assert_python_success $? "$output"; then
		test_failure "user should be allowed to MAIL FROM a user for which they are a permitted sender: $(python_error "$output")"
	fi
	assert_check_logs

	# login as bob, send from alias to alice
	# expect failure because bob is not a permitted-sender
	start_log_capture
	record "[Mailing to alice from bob as alias/mary]"
	output="$($PYMAIL -f $alias -to $alice alice $PRIVATE_IP $bob bob 2>&1)"
	assert_python_failure $? "$output" "SMTPRecipientsRefused" "not owned by user"
	check_logs

	delete_user $alice
	delete_user $bob
	delete_permitted_senders_group $alias
	create_alias_group $alias
	test_end
}



suite_start "mail-from"

test_permitted_sender_fail
test_permitted_sender_alias
test_permitted_sender_explicit

suite_end
