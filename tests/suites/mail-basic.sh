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
# Test basic mail functionality



test_trial_send_local() {
	# use sendmail -bv to test mail delivery without actually mailing
	# anything
	test_start "trial_send_local"

	# create a standard users alice and bobo
	local alice="alice@somedomain.com" bob="bob@somedomain.com"
	create_user "$alice" "alice"
	create_user "$bob" "bob"

	# test delivery, but don't actually mail it
	start_log_capture
	sendmail_bv_send "$alice" 30 "$bob"
	assert_check_logs
	have_test_failures && record_captured_mail

	# clean up / end
	delete_user "$alice"
	delete_user "$bob"
	test_end
}

test_trial_send_remote() {
	# use sendmail -bv to test mail delivery without actually mailing
	# anything
	test_start "trial_send_remote"
	if skip_test remote-smtp; then
		test_end
		return 0
	fi
	start_log_capture
	sendmail_bv_send "test@google.com" 120
	assert_check_logs
	have_test_failures && record_captured_mail
	test_end
}


test_self_send_receive() {
	# test sending mail to yourself
	test_start "self-send-receive"
	# create standard user alice
	local alice="alice@somedomain.com"
	create_user "$alice" "alice"

	# test actual delivery
	start_log_capture
	record "[Sending mail to alice as alice]"
	local output
	output="$($PYMAIL $PRIVATE_IP $alice alice 2>&1)"
	local code=$?
	record "$output"
	if [ $code -ne 0 ]; then
		test_failure "$PYMAIL exit code $code: $output"
	fi
	assert_check_logs

	delete_user "$alice"
	test_end
}



suite_start "mail-basic" ensure_root_user

test_trial_send_local
test_trial_send_remote
test_self_send_receive

suite_end

