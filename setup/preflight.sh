# Are we running as root?
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root. Please re-run like this:"
	echo
	echo "sudo $0"
	echo
	exit
fi

# Check that we are running on Ubuntu 14.04 LTS (or 14.04.xx).
if [ `lsb_release -d | sed 's/.*:\sUbuntu *//' | cut -d'.' -f1` -lt 12 ]; then
	echo "Mail-in-a-Box only supports being installed on Ubuntu 12 and newer, sorry. You are running:"
	echo
	lsb_release -d | sed 's/.*:\s*//'
	echo
	echo "We can't write scripts that run on every possible setup, sorry."
	exit
fi

# Check that we have enough memory. Skip the check if we appear to be
# running inside of Vagrant, because that's really just for testing.
TOTAL_PHYSICAL_MEM=$(head -n 1 /proc/meminfo | awk '{print $2}')
if [ $TOTAL_PHYSICAL_MEM -lt 786432 ]; then
if [ ! -d /vagrant ]; then
	echo "Your Mail-in-a-Box needs more than $TOTAL_PHYSICAL_MEM MB RAM."
	echo "Please provision a machine with at least 768 MB, 1 GB recommended."
	exit
fi
fi
