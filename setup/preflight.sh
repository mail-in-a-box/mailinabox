# Are we running as root?
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root. Please re-run like this:"
	echo
	echo "sudo setup/start.sh"
	echo
	exit
fi

# Check that we are running on Ubuntu 14.04 LTS (or 14.04.xx).
if [ "`lsb_release -d | sed 's/.*:\s*//' | sed 's/14\.04\.[0-9]/14.04/' `" != "Ubuntu 14.04 LTS" ]; then
	echo "Mail-in-a-Box only supports being installed on Ubuntu 14.04, sorry. You are running:"
	echo
	lsb_release -d | sed 's/.*:\s*//'
	echo
	echo "We can't write scripts that run on every possible setup, sorry."
	exit
fi

# Check that we have enough memory. Skip the check if we appear to be
# running inside of Vagrant, because that's really just for testing.
TOTAL_PHYSICAL_MEM=$(free -m | grep ^Mem: | sed "s/^Mem: *\([0-9]*\).*/\1/")
if [ $TOTAL_PHYSICAL_MEM -lt 768 ]; then
if [ ! -d /vagrant ]; then
	echo "Your Mail-in-a-Box needs more than $TOTAL_PHYSICAL_MEM MB RAM."
	echo "Please provision a machine with at least 768 MB, 1 GB recommended."
	exit
fi
fi
