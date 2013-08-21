# Base system configuration.

sudo apt-get -q update
sudo apt-get -q -y upgrade

# Basic packages.

sudo apt-get -q -y install sqlite3

# Turn on basic services:
#
#   ntp: keeps the system time correct
#
#   fail2ban: scans log files for repeated failed login attempts and blocks the remote IP at the firewall
#
# These services don't need further configuration and are started immediately after installation.

sudo apt-get install -q -y ntp fail2ban

# Turn on the firewall. First allow incoming SSH, then turn on the firewall. Additional open
# ports will be set up in the scripts that set up those services.
sudo ufw allow ssh
#sudo ufw allow domain
#sudo ufw allow http
#sudo ufw allow https
sudo ufw --force enable

# Mount the storage volume.
export STORAGE_ROOT=/home/ubuntu/storage
mkdir -p storage


