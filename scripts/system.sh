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

# Turn on the firewall. First allow incoming SSH, then turn on the firewall.
# Other ports will be opened at the point where we set up those services.
apt-get -q -y install ufw;
ufw allow ssh;
ufw --force enable;

