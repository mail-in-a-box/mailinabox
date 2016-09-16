source /etc/mailinabox.conf # load global vars

cat <<EOF >> /etc/ssh/login-alert.sh
#!/bin/sh
sender="bot@PRIMARY_HOSTNAME"
recepient="admin@$PRIMARY_HOSTNAME"

if [ "$PAM_TYPE" != "close_session" ]; then
    subject="SSH Login: $PAM_USER from $PAM_RHOST"
    # Message to send, e.g. the current environment variables.
    message="If you don't recognize this login, your key or password may be compromised."
    echo "$message" | mailx -r "$sender" -s "$subject" "$recepient"
fi
EOF

chmod +x /etc/ssh/login-alert.sh

echo 'session optional pam_exec.so seteuid /etc/ssh/login-alert.sh' >> /etc/pam.d/sshd
