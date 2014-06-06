#!/bin/bash

# Check that SSH login with password is disabled. Stop if it's enabled.
if grep -q "^PasswordAuthentication yes" /etc/ssh/sshd_config \
 || ! grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config ; then
        echo "The SSH server on this machine permits password-based login."
        echo "A more secure way to log in is using a public key."
        echo ""
        echo "Add your SSH public key to $HOME/.ssh/authorized_keys, check"
        echo "check that you can log in without a password, set the option"
        echo "'PasswordAuthentication no' in /etc/ssh/sshd_config, and then"
        echo "restart the openssh via 'sudo service ssh restart'"
        exit
fi

