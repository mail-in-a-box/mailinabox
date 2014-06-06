source setup/functions.sh # load our functions

# Base system configuration.

apt-get -qq update
apt-get -qq -y upgrade

# Install basic utilities.

apt_install python3 wget curl bind9-host

# Turn on basic services:
#
#   ntp: keeps the system time correct
#
#   fail2ban: scans log files for repeated failed login attempts and blocks the remote IP at the firewall
#
# These services don't need further configuration and are started immediately after installation.

apt_install ntp fail2ban

if [ -z "$DISABLE_FIREWALL" ]; then
	# Turn on the firewall. First allow incoming SSH, then turn on the firewall.
	# Other ports will be opened at the point where we set up those services.
	#
	# Various virtualized environments like Docker and some VPSs don't provide
	# a kernel that supports iptables. To avoid error-like output in these cases,
	# let us disable the firewall.
	apt_install ufw
	ufw_allow ssh;
	ufw --force enable;
fi