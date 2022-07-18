


test_zpush_logon() {
    test_start "logon"

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


test_zpush_fail2ban() {
    test_start "fail2ban"
    
    # create regular user with password "alice"
    local alice="alice@somedomain.com"
    local alice_pw="alice"
    create_user "$alice" "$alice_pw"

    # The default fail2ban configuration ignores failed logins coming
    # from our private ip and localhost. Change it so that it does not
    # ignore the private ip in the z-push configuration only. Also
    # change the allowed number of failures to a lower value to speed
    # up the tests.
    
    record "[override default fail2ban options]"
    local fail2ban_conf_temp="/tmp/runner_zpush_fail2ban.conf"
    if [ -e "$fail2ban_conf_temp" ]; then
        # if this test was somehow interrupted, the temp still exists
        record "1. restore /etc/fail2ban/jail.d/mailinabox.conf"
        cp "$fail2ban_conf_temp" "/etc/fail2ban/jail.d/mailinabox.conf" 1>>$TEST_OF 2>&1 || test_failure "Unable to setup test - could not restore fail2ban config"
    else
        record "1. duplicate /etc/fail2ban/jail.d/mailinabox.conf"
        cp --no-clobber /etc/fail2ban/jail.d/mailinabox.conf $fail2ban_conf_temp 1>>$TEST_OF 2>&1 || test_failure "Unable to setup test - could not copy fail2ban config"
    fi    

    if ! have_test_failures; then
        record "2. edit /etc/fail2ban/jail.d/mailinabox.conf"
        $EDITCONF /etc/fail2ban/jail.d/mailinabox.conf \
                  -ini-section z-push \
                  "ignoreip=127.0.0.1/8 ::1" \
                  "maxretry=5" >>$TEST_OF 2>&1 ||
            test_failure "Unable to setup test - changing fail2ban config failed"
        if ! have_test_failures; then
            record "3. reload fail2ban"
            systemctl reload fail2ban >>$TEST_OF 2>&1 || test_failure "Unable to setup test - reloading fail2ban failed"
        fi
        
        # reset fail2ban - unban all
        if ! have_test_failures; then
            record "4. unban all"
            fail2ban-client unban --all >>$TEST_OF 2>&1 ||
                test_failure "Unable to setup test - executing unban --all failed"
        fi
    fi
    
    if have_test_failures; then
        test_end
        return
    fi


    # log in a bunch of times with wrong password
    local devid="device1"
    local devtype="iPhone"
    local n=0 t1 t2 t
    local total=10
    local banned=no
    local code=0

    start_log_capture
    
    record "[log in $total times with wrong password]"
    while ! have_test_failures && [ $n -lt $total ]; do
        t1=$(date +%s)
        rest_urlencoded POST "https://$PRIVATE_IP/Microsoft-Server-ActiveSync?Cmd=Ping&DeviceId=$devid&DeviceType=$devtype" "$alice" "bad-alice" --insecure 2>>$TEST_OF
        code=$?
        t2=$(date +%s)
        let t="$t2 - $t1"
        record "TRY $n (${t}s): result code $code"
        if [ $code -eq 0 ]; then
            test_failure "Unexpected logon success"
            continue
        elif grep -F 'code 7' <<<"$REST_ERROR" >/dev/null; then
            # curl error for connection refused
            record "BANNED!"
            banned=yes
            break
        elif [ $REST_HTTP_CODE -eq 401 ]; then
            # assume a logon failure, reset log monitor
            check_logs false zpush nginx_access
            start_log_capture
        else
            test_failure "Error in REST call to z-push: $REST_ERROR"
            assert_check_logs zpush nginx_access
            continue
        fi
        record "$REST_OUTPUT"
        let n+=1
    done

    if ! have_test_failures; then
        if [ "$banned" == "no" ]; then
            test_failure "Multiple failed logons did not ban ip"

        else
            record "[logging in with correct password should also fail]"
            rest_urlencoded POST "https://$PRIVATE_IP/Microsoft-Server-ActiveSync?Cmd=Ping&DeviceId=$devid&DeviceType=$devtype" "$alice" "$alice_pw" --insecure 2>>$TEST_OF
            code=$?
            record "result: $code"
            if [ $code -eq 0 ]; then
                test_failure "Expected user logon to fail due to ban"
            elif grep -F 'code 7' <<<"$REST_ERROR" >/dev/null; then
                # curl error for connection refused
                record "OK: banned: $REST_ERROR"
            else
                test_failure "Error in REST call to z-push: $REST_ERROR"
            fi
        fi
    fi

    # delete alice
    delete_user "$alice"
    
    # reset fail2ban
    record "[reset fail2ban config changes]"
    record "restore /etc/fail2ban/jail.d/mailinabox.conf"
    cp $fail2ban_conf_temp /etc/fail2ban/jail.d/mailinabox.conf
    if [ $? -ne 0 ]; then
        test_failure "Unable to restore fail2ban config"
    else
        systemctl reload fail2ban >>$TEST_OF 2>&1 ||
            test_failure "Unable reload fail2ban"
    fi
    rm -f $fail2ban_conf_temp

    fail2ban-client unban --all >>$TEST_OF 2>&1 ||
        test_failure "Unable to execute unban --all"
        
    # done
    test_end
}


suite_start "z-push" zpush_start

test_zpush_logon
test_zpush_fail2ban

suite_end zpush_end

