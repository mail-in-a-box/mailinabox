source scripts/functions.sh # load our functions

# Base system configuration.

apt-get -q -q update
apt-get -q -y upgrade

# Install openssh-server to ensure that the end result is consistent across all Mail-in-a-Boxes.
apt_install openssh-server

# Check that SSH login with password is disabled. Stop if it's enabled.
if grep -q "^PasswordAuthentication yes" /etc/ssh/sshd_config \
 || ! grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config ; then
        echo
        echo "The SSH server on this machine permits password-based login."
        echo "Add your SSH public key to $HOME/.ssh/authorized_keys, check"
        echo "check that you can log in without a password, set the option"
        echo "'PasswordAuthentication no' in /etc/ssh/sshd_config, and then"
        echo "restart the openssh via 'sudo service ssh restart'"
        exit
fi

apt_install python3

# Turn on basic services:
#
#   ntp: keeps the system time correct
#
#   fail2ban: scans log files for repeated failed login attempts and blocks the remote IP at the firewall
#
# These services don't need further configuration and are started immediately after installation.

apt_install ntp fail2ban

# Turn on the firewall. First allow incoming SSH, then turn on the firewall.
# Other ports will be opened at the point where we set up those services.
apt_install ufw
ufw allow ssh;
ufw --force enable;

