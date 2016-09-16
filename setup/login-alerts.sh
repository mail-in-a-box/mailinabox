#!/bin/bash

# Create a script to be called when a user logs in
cat << 'EOF' > /etc/ssh/login-alert.sh
#!/bin/bash

source /etc/mailinabox.conf # load global vars

if [ "$PAM_TYPE" != "close_session" ]; then
    # send alert
    sendEmail -q -f "bot@$PRIMARY_HOSTNAME" -t "admin@$PRIMARY_HOSTNAME" -u "SSH Login: $PAM_USER from $PAM_RHOST" -m "If you don't recognize this login, your key or password may be compromised."
fi
EOF

chmod +x /etc/ssh/login-alert.sh # make script executable

if grep -Fq "login-alert" /etc/pam.d/sshd # if line has already been added to sshd
then
    : # do nothing
else
    echo 'session optional pam_exec.so seteuid /etc/ssh/login-alert.sh' >> /etc/pam.d/sshd # otherwise add the line
fi
