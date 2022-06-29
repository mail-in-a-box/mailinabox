


test_zpush_logon() {
    test_start "zpush-logon"

    # create regular user alice
    local alice="alice@somedomain.com"
    local alice_pw="123alice"
    create_user "$alice" "$alice_pw"

    # issue a "Ping" command to z-push
    local devid="device1"
    local devtype="iPhone"
    record "[issue a 'Ping' command]"
    start_log_capture
    rest_urlencoded POST "/Microsoft-Server-ActiveSync?Cmd=Ping&DeviceId=$devid&DeviceType=$devtype" "$alice" "$alice_pw" 2>>$TEST_OF
    if [ $? -ne 0 ]; then
        test_failure "Error in REST call to z-push: $REST_ERROR"
    fi
    record "$REST_OUTPUT"
    
    assert_check_logs zpush nginx_access

    if ! have_test_failures; then
        # Make sure we have Logon() calls for all three combined
        # backends by examining the z-push.log file (which has
        # LOGLEVEL set to DEBUG by
        # _zpush-functions.sh:zpush_start)
        #
        # Logons were successful because of the assert_check_logs
        # call above.
        #
        # In addition, nginx/access.log will have entries for rest
        # calls made by z-push to nextcloud, but we're not looking at
        # those here. Any nextcloud failures will produce a failure in
        # the Ping command and cause a test_failure by the
        # assert_check_logs call above, so it's not needed.

        # expected_backends must be sorted
        local expected_backends="BackendCalDAV BackendCardDAV BackendIMAP Combined"
        
        # Example z-push.log file entries:
        # -------------------------
        # DD/MM/YYYY HH:MM:SS [33891] [DEBUG] [alice@somedomain.com] BackendIMAP->Logon(): User 'alice@somedomain.com' is authenticated on '{127.0.0.1:993/imap/ssl/norsh/novalidate-cert}'
        # DD/MM/YYYY HH:MM:SS [33891] [DEBUG] [alice@somedomain.com] BackendCalDAV->Logon(): User 'alice@somedomain.com' is authenticated on CalDAV 'https://127.0.0.1:443/caldav/calendars/alice@somedomain.com/'
        # DD/MM/YYYY HH:MM:SS [33891] [DEBUG] [alice@somedomain.com] BackendCardDAV->Logon(): User 'alice@somedomain.com' is authenticated on 'https://127.0.0.1:443/carddav/addressbooks/alice@somedomain.com/'

        local count
        let count="$ZPUSH_LOG_LINECOUNT + 1"
        local matches
        matches=( $(tail --lines=+$count /var/log/z-push/z-push.log 2>>$TEST_OF | grep -F -- "->Logon(" 2>>$TEST_OF | sed -E "s/^.* (.*)->Logon\\(.*$/\\1/" 2>>$TEST_OF | sort | uniq) )
        record "found successful logons for backends: ${matches[*]}"
        if [ "${matches[*]}" != "$expected_backends" ]
        then
            test_failure "Expected logons for backends '$expected_backends', but got '${matches[*]}'"
        fi
    fi
    
    delete_user "$alice"
    test_end
}


suite_start "z-push" zpush_start

test_zpush_logon

suite_end zpush_end

