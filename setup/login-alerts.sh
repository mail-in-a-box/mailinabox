function get_default_hostname {
	# Guess the machine's hostname. It should be a fully qualified
	# domain name suitable for DNS. None of these calls may provide
	# the right value, but it's the best guess we can make.
	set -- $(hostname --fqdn      2>/dev/null ||
                 hostname --all-fqdns 2>/dev/null ||
                 hostname             2>/dev/null)
	printf '%s\n' "$1" # return this value
}

echo '
#!/bin/sh
# Change these two lines:
sender="bot@"
sender+=get_default_hostname
recepient="admin@"
recepient+=get_default_hostname

if [ "$PAM_TYPE" != "close_session" ]; then
    host="`hostname`"
    subject="SSH Login: $PAM_USER from $PAM_RHOST on $host"
    # Message to send, e.g. the current environment variables.
    message="If you don't recognize this login, your key or password may be compromised."
    echo "$message" | mailx -r "$sender" -s "$subject" "$recepient"
fi' > /etc/ssh/login-alert.sh

chmod +x /etc/ssh/login-alert.sh

echo 'session optional pam_exec.so seteuid /etc/ssh/login-alert.sh' >> /etc/pam.d/sshd
