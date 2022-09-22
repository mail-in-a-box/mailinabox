# -*- indent-tabs-mode: t; tab-width: 4; -*-
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####


clear_postfix_queue() {
	record "[Clear postfix queue]"
	postsuper -d ALL >>$TEST_OF 2>&1 || die "Unable to clear postfix undeliverable mail queue"
}


ensure_root_user() {
	# ensure there is a local email account for root.
	#
	# on exit, ROOT, ROOT_MAILDROP, and ROOT_DN are set, and if no
	# account exists, a new root@$(hostname --fqdn) is created having a
	# random password
	#
	if [ ! -z "$ROOT_MAILDROP" ]; then
		# already have it
		return
	fi
	ROOT="${USER}@$(hostname --fqdn || hostname)"
	record "[Find user $ROOT]"
	get_attribute "$LDAP_USERS_BASE" "mail=$ROOT" "maildrop"
	ROOT_MAILDROP="$ATTR_VALUE"
	ROOT_DN="$ATTR_DN"
	if [ -z "$ROOT_DN" ]; then
		local pw="$(generate_password 128)"
		create_user "$ROOT" "$pw"
		record "new password is: $pw"
		ROOT_DN="$ATTR_DN"
		ROOT_MAILDROP="$ROOT"
	else
		record "$ROOT => $ROOT_DN ($ROOT_MAILDROP)"
	fi
}


dovecot_mailbox_home() {
	local email="$1"
	local mailbox="${2:-INBOX}"
	local path
	/usr/bin/doveadm mailbox path -u "$email" "$mailbox"
	#echo -n "${STORAGE_ROOT}/mail/mailboxes/"
	#awk -F@ '{print $2"/"$1}' <<< "$email"
}


start_log_capture() {
	SYS_LOG_LINECOUNT=$(wc -l /var/log/syslog 2>>$TEST_OF | awk '{print $1}') || die "could not access /var/log/syslog"
	SLAPD_LOG_LINECOUNT=0
	if [ -e /var/log/ldap/slapd.log ]; then
		SLAPD_LOG_LINECOUNT=$(wc -l /var/log/ldap/slapd.log 2>>$TEST_OF | awk '{print $1}') || die "could not access /var/log/ldap/slapd.log"
	fi
	MAIL_ERRLOG_LINECOUNT=0
	if [ -e /var/log/mail.err ]; then
		MAIL_ERRLOG_LINECOUNT=$(wc -l /var/log/mail.err 2>>$TEST_OF | awk '{print $1}') || die "could not access /var/log/mail.err"
	fi
	MAIL_LOG_LINECOUNT=0
	if [ -e /var/log/mail.log ]; then
		MAIL_LOG_LINECOUNT=$(wc -l /var/log/mail.log 2>>$TEST_OF | awk '{print $1}') || die "could not access /var/log/mail.log"
	fi
	DOVECOT_LOG_LINECOUNT=$(doveadm log errors 2>>$TEST_OF | wc -l | awk '{print $1}') || die "could not access doveadm error logs"
	ZPUSH_LOG_LINECOUNT=0
	if [ -e /var/log/z-push/z-push.log ]; then
		# z-push-errors.log only has errors, but z-push.log has errors
		# and other logging, so use that
		ZPUSH_LOG_LINECOUNT=$(wc -l /var/log/z-push/z-push.log 2>>$TEST_OF | awk '{print $1}') || die "could not access /var/log/z-push/z-push.log"
	fi
	NGINX_ACCESS_LOG_LINECOUNT=0
	if [ -e /var/log/nginx/access.log ]; then
		NGINX_ACCESS_LOG_LINECOUNT=$(wc -l /var/log/nginx/access.log 2>>$TEST_OF | awk '{print $1}') || die "could not access /var/log/nginx/access.log"
	fi
}

start_mail_capture() {
	local email="$1"
	record "[Start mail capture $email]"
	DOVECOT_CAPTURE_USER="$email"
	DOVECOT_CAPTURE_FILECOUNT=()
	DOVECOT_CAPTURE_MAILBOXES=(INBOX Spam)
	for mailbox in ${DOVECOT_CAPTURE_MAILBOXES[@]}; do
		local mbhome
		mbhome="$(dovecot_mailbox_home "$email" "$mailbox" 2>>$TEST_OF)"
		[ $? -ne 0 ] && die "Error accessing $mailbox of $email"
		local newdir="$mbhome/new"
		local count=0
		if [ -e "$newdir" ]; then
			count=$(ls "$newdir" 2>>$TEST_OF | wc -l)
			[ $? -ne 0 ] && die "Error accessing mailbox of $email"			
		fi
		DOVECOT_CAPTURE_FILECOUNT+=($count)
		record "$mailbox location: $mbhome"
		record "$mailbox has $count files"
	done
}

dump_capture_logs() {
	# dump log files
	record "[capture log dump]"
	record ""
	record "============= SYSLOG ================"
	tail --lines=+$SYS_LOG_LINECOUNT /var/log/syslog 2>>$TEST_OF
	record ""
	record "============= SLAPD ================="
	tail --lines=+$SLAPD_LOG_LINECOUNT /var/log/ldap/slapd.log 2>>$TEST_OF
	record ""
	record "============= MAIL.ERR =============="
	tail --lines=+$MAIL_ERRLOG_LINECOUNT /var/log/mail.err 2>>$TEST_OF
	record ""
	record "============= MAIL.LOG =============="
	tail --lines=+$MAIL_LOG_LINECOUNT /var/log/mail.log 2>>$TEST_OF
	record ""
	record "============= DOVECOT ERRORS =============="
	doveadm log errors | tail --lines=+$DOVECOT_LOG_LINECOUNT 2>>$TEST_OF
	record ""
	record "============= Z-PUSH LOG =============="
	tail --lines=+$ZPUSH_LOG_LINECOUND /var/log/z-push/z-push.log 2>>$TEST_OF
}

detect_syslog_error() {
	record
	record "[Detect syslog errors]"
	local count
	let count="$SYS_LOG_LINECOUNT + 1"
	tail --lines=+$count /var/log/syslog 2>>$TEST_OF | (
		let ec=0 # error count
		let wc=0 # warning count
		while read line; do
			# named[7940]: dispatch 0x7f460c02c3a0: shutting down due to TCP receive error: 199.249.112.1#53: connection reset
			awk '
/rsyslogd: action .* (suspended|resumed)/ { exit 2 }
!/nsd\[[0-9]+\]/ && /warning:/	{ exit 1 }
/nsd\[[0-9]+\]: error: Cannot open .*nsd\.log/ { exit 2 }
/named\[[0-9]+\]:.* receive error: .*: connection reset/ { exit 2 }
/(fatal|reject|error):/	 { exit 1 }
/Error in /			{ exit 1 }
/Exception on /     { exit 1 }
/named\[[0-9]+\]:.* verify failed/ { exit 1 }
' \
				>>$TEST_OF 2>&1 <<< "$line"
			r=$?
			if [ $r -eq 1 ]; then
				let ec+=1
				record "$F_DANGER[ERROR] $line$F_RESET"
			elif [ $r -eq 2 ]; then
				let wc+=1
				record "$F_WARN[ WARN] $line$F_RESET"
			else
				if [ "$DETECT_SYSLOG_ERROR_OUTPUT" != "brief" ]; then
					record "[   OK] $line"
				fi
			fi
		done
		[ $ec -gt 0 ] && exit 0
		exit 1 # no errors
	)
	local x=( ${PIPESTATUS[*]} )
	[ ${x[0]} -ne 0 ] && die "Could not read /var/log/syslog"
	return ${x[1]}
}

detect_slapd_log_error() {
	record
	record "[Detect slapd log errors]"
	local count
	let count="SLAPD_LOG_LINECOUNT + 1"
	tail --lines=+$count /var/log/ldap/slapd.log 2>>$TEST_OF | (
		let ec=0 # error count
		let wc=0 # warning count
		let ignored=0
		while read line; do
			# slapd error 68 = "entry already exists". Mark it as a
			# warning because code often attempts to add entries
			# silently ignoring the error, which is expected behavior
			#
			# slapd error 32 = "no such object". Mark it as a warning
			# because code often attempts to resolve a dn (eg member)
			# that is orphaned, so no entry exists. Code may or may
			# not care about this.
			#
			# slapd error 4 - "size limit exceeded". Mark it as a warning
			# because code often attempts to find just 1 entry so sets
			# the limit to 1 purposefully.
			#
			# slapd error 20 - "attribute or value exists". Mark it as a
			# warning becuase code often attempts to add a new value
			# to an existing attribute and doesn't care if the new
			# value fails to add because it already exists.
			#
			awk '
/SEARCH RESULT.*err=(32|4) / { exit 2}
/RESULT.*err=(68|20) / { exit 2 }
/ not indexed/ { exit 2 }
/RESULT.*err=[^0]/ { exit 1 }
/(get|test)_filter/		  { exit 3 }
/mdb_(filter|list)_candidates/	{ exit 3 }
/:(		| #011| )(AND|OR|EQUALITY)/ { exit 3 }
' \
				>>$TEST_OF 2>&1 <<< "$line"
			r=$?
			if [ $r -eq 1 ]; then
				let ec+=1
				record "$F_DANGER[ERROR] $line$F_RESET"
			elif [ $r -eq 2 ]; then
				let wc+=1
				record "$F_WARN[ WARN] $line$F_RESET"
			elif [ $r -eq 3 ]; then
				let ignored+=1
			else
				if [ "$DETECT_SLAPD_LOG_ERROR_OUTPUT" != "brief" ]; then
					record "[   OK] $line"
				fi
			fi
		done
		record "$ignored unreported/ignored log lines"
		[ $ec -gt 0 ] && exit 0
		exit 1 # no errors
	)
	local x=( ${PIPESTATUS[*]} )
	[ ${x[0]} -ne 0 ] && die "Could not read /var/log/ldap/slapd.log"
	return ${x[1]}
}


detect_mail_log_error() {
	record
	record "[Detect mail log errors]"
	local count
	let count="$MAIL_LOG_LINECOUNT + 1"
	if [ ! -e /var/log/mail.log ]; then
		return 0
	fi
	# prefer mail.log over `dovadm log errors` because the latter does
	# not have as much output - it's helpful to have success logs when
	# diagnosing logs...
	cat /var/log/mail.log 2>>$TEST_OF | tail --lines=+$count | (
		let ec=0 # error count
		let ignored=0
		while read line; do
			awk '
/status=(bounced|deferred|undeliverable)/  { exit 1 }
/warning:/ && /spamhaus\.org: RBL lookup error:/ { exit 2 }
!/postfix\/qmgr/ && /warning:/	{ exit 1 }
/LDAP server, reconnecting/ { exit 2 }
/postfix/ { exit 2 }
/auth failed/  { exit 1 }
/ Error: /			  { exit 1 }
/(fatal|reject|error):/	 { exit 1 }
/Error in /			{ exit 1 }
/Exception on /     { exit 1 }
' \
				>>$TEST_OF 2>&1 <<< "$line"
			r=$?
			if [ $r -eq 1 ]; then
				let ec+=1
				record "$F_DANGER[ERROR] $line$F_RESET"
			elif [ $r -eq 2 ]; then
				let ignored+=1
			else
				record "[   OK] $line"
			fi
		done
		record "$ignored unreported/ignored log lines"
		[ $ec -gt 0 ] && exit 0
		exit 1 # no errors
	)
	local x=( ${PIPESTATUS[*]} )
	[ ${x[0]} -ne 0 -o ${x[1]} -ne 0 ] && die "Could not read mail log"
	return ${x[2]}
}

detect_zpush_log_error() {
	record
	record "[Detect z-push log errors]"
	local count
	let count="$ZPUSH_LOG_LINECOUNT + 1"
	tail --lines=+$count /var/log/z-push/z-push.log 2>>$TEST_OF | (
		let ec=0 # error count
		let wc=0 # warning count
		let ignored=0
		while read line; do
			awk '
/\[FATAL\]/ && /Unable to read filename .\/var\/lib\/z-push\/users. after 3 retries/ { exit 2 }
/\[FATAL\]/ { exit 1 }
/\[WARN\]/ { exit 2 }
' \
				>>$TEST_OF 2>&1 <<< "$line"
			r=$?
			if [ $r -eq 1 ]; then
				let ec+=1
				record "$F_DANGER[ERROR] $line$F_RESET"
			elif [ $r -eq 2 ]; then
				let wc+=1
				record "$F_WARN[ WARN] $line$F_RESET"
			elif [ $r -eq 3 ]; then
				let ignored+=1
			else
				record "[   OK] $line"
			fi
		done
		record "$ignored unreported/ignored log lines"
		[ $ec -gt 0 ] && exit 0
		exit 1 # no errors
	)
	local x=( ${PIPESTATUS[*]} )
	[ ${x[0]} -ne 0 ] && die "Could not read /var/log/z-push/z-push.log"
	return ${x[1]}
}

detect_nginx_access_log_error() {
	record
	record "[Detect nginx access log errors]"
	local count
	let count="$NGINX_ACCESS_LOG_LINECOUNT + 1"
	tail --lines=+$count /var/log/nginx/access.log 2>>$TEST_OF | (
		let ec=0 # error count
		let wc=0 # warning count
		let ignored=0
		while read line; do
			cat <<EOF | python3
import csv,os,sys
for row in csv.reader(sys.stdin, delimiter=' '):
    try:
        status=int(row[6])
        if status >= 400: os.exit(1)
    except:
        pass
    #print("ROW=( '%s' )" % "','".join(row))
EOF
			>>$TEST_OF 2>&1 <<< "$line"
			r=$?
			if [ $r -eq 1 ]; then
				let ec+=1
				record "$F_DANGER[ERROR] $line$F_RESET"
			elif [ $r -eq 2 ]; then
				let wc+=1
				record "$F_WARN[ WARN] $line$F_RESET"
			elif [ $r -eq 3 ]; then
				let ignored+=1
			else
				record "[   OK] $line"
			fi
		done
		record "$ignored unreported/ignored log lines"
		[ $ec -gt 0 ] && exit 0
		exit 1 # no errors
	)
	local x=( ${PIPESTATUS[*]} )
	[ ${x[0]} -ne 0 ] && die "Could not read /var/log/nginx/access.log"
	return ${x[1]}
}

flush_logs() {
	local pid
	if [ -e /var/run/rsyslogd.pid ]; then
		# the pid file won't exist if rsyslogd was started with -iNONE
		pid=$(cat /var/run/rsyslogd.pid)
	else
		pid=$(/usr/bin/pidof rsyslogd)
	fi
	if [ ! -z "$pid" ]; then
		kill -HUP $pid >>$TEST_OF 2>&1
		sleep 2
	fi
}

check_logs() {
	local assert="${1:-false}"
	[ "$1" == "true" -o "$1" == "false" ] && shift
	local types=($@)
	[ ${#types[@]} -eq 0 ] && types=(syslog slapd mail)
	
	# flush records
	flush_logs

	if array_contains syslog ${types[@]}; then
		detect_syslog_error && $assert &&
			test_failure "detected errors in syslog"
	fi
	
	if array_contains slapd ${types[@]}; then
		detect_slapd_log_error && $assert &&
			test_failure "detected errors in slapd log"
	fi
	
	if array_contains mail ${types[@]}; then
		detect_mail_log_error && $assert &&
			test_failure "detected errors in mail log"
	fi

	if array_contains zpush ${types[@]} || array_contains z-push ${types[@]}
	then
		detect_zpush_log_error && $assert &&
			test_failure "detected errors in z-push.log"
	fi

	if array_contains nginx_access ${types[@]}; then
		detect_nginx_access_log_error && $assert &&
			test_failure "detected errors in nginx access log"
	fi
}

assert_check_logs() {
	check_logs true $@
}

grep_postfix_log() {
	local msg="$1"
	local count
	let count="$MAIL_LOG_LINECOUNT + 1"
	flush_logs
	tail --lines=+$count /var/log/mail.log 2>>$TEST_OF | grep -iF "$msg" >/dev/null 2>>$TEST_OF
	return $?
}

wait_mail() {
	local x mail_files elapsed max_s="${1:-60}"
	let elapsed=0
	record "[Waiting for mail to $DOVECOT_CAPTURE_USER]"
	while [ $elapsed -lt $max_s ]; do
		mail_files=( $(get_captured_mail_files) )
		[ ${#mail_files[*]} -gt 0 ] && break
		sleep 1
		let elapsed+=1
		let x="$elapsed % 10"
		[ $x -eq 0 ] && record "...~${elapsed} seconds has passed"
	done
	if [ $elapsed -ge $max_s ]; then
		record "Timeout waiting for mail"
		return 1
	fi
	record "new mail files:"
	for x in ${mail_files[@]}; do
		record "$x"
	done
}

get_captured_mail_files() {
	local idx=0
	while [ $idx -lt ${#DOVECOT_CAPTURE_MAILBOXES[*]} ]; do
		local mailbox=${DOVECOT_CAPTURE_MAILBOXES[$idx]}
		local filecount=${DOVECOT_CAPTURE_FILECOUNT[$idx]}
		local mbhome
		mbhome="$(dovecot_mailbox_home "$DOVECOT_CAPTURE_USER" "$mailbox" 2>>$TEST_OF)"
		[ $? -ne 0 ] && die "Error accessing mailbox of $email"
		local newdir="$mbhome/new"
		[ ! -e "$newdir" ] && return 0
		local count
		let count="$filecount + 1"
		# output absolute path names
		local file
		for file in $(ls "$newdir" 2>>$TEST_OF | tail --lines=+${count}); do
			echo "$newdir/$file"
		done
		let idx+=1
	done
}

record_captured_mail() {
	local files=( $(get_captured_mail_files) )
	local file
	for file in ${files[@]}; do
		record
		record "[Captured mail file: $file]"
		cat "$file" >>$TEST_OF 2>&1
	done
}


sendmail_bv_send() {
	# test sending mail, but don't actually send it...
	local recpt="$1"
	local timeout="$2"
	local bvfrom from="$3"
	# delivery status is emailed back to us, or 'from' if supplied
	clear_postfix_queue
	if [ -z "$from" ]; then
		ensure_root_user
		start_mail_capture "$ROOT"
	else
		bvfrom="-f $from"
		start_mail_capture "$from"
	fi
	record "[Running sendmail -bv $bvfrom]"
	sendmail $bvfrom -bv "$recpt" >>$TEST_OF 2>&1
	if [ $? -ne 0 ]; then
		test_failure "Error executing sendmail"
	else
		wait_mail $timeout || test_failure "Timeout waiting for delivery report"
	fi	  
}


assert_python_success() {
	local code="$1"
	local output="$2"
	record "$output"
	record
	record "python exit code: $code"
	if [ $code -ne 0 ]; then
		test_failure "unable to process mail: $(python_error "$output")"
		return 1
	fi
	return 0
}

assert_python_failure() {
	local code="$1"
	local output="$2"
	shift; shift
	record "$output"
	record
	record "python exit code: $code"
	if [ $code -eq 0 ]; then
		test_failure "python succeeded but expected failure"
		return 1
	fi
	local look_for
	for look_for; do
		if [ ! -z "$look_for" ] && ! grep "$look_for" <<< "$output" 1>/dev/null
		then
			test_failure "unexpected python failure: $(python_error "$output")"
			return 1
		fi
	done
	return 0
}
