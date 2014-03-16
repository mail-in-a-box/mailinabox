# Base system configuration.

apt-get -q -q update
apt-get -q -y upgrade

apt-get -q -y install python3

# Turn on basic services:
#
#   ntp: keeps the system time correct
#
#   fail2ban: scans log files for repeated failed login attempts and blocks the remote IP at the firewall
#
# These services don't need further configuration and are started immediately after installation.

apt-get install -q -y ntp fail2ban

# Turn on the firewall. First allow incoming SSH, then turn on the firewall. Additional open
# ports will be set up in the scripts that set up those services. Some virtual machine providers
# (ehm, Rimuhosting) don't provide a kernel that supports ufw, so let advanced users skip it.
if [ -z "$DISABLE_FIREWALL" ]; then
	ufw allow ssh;
	ufw --force enable;
fi

