# Are we running as root?
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root. Please re-run like this:"
	echo
	echo "sudo $0"
	echo
	exit 1
fi

# Check that we are running on Ubuntu 14.04 LTS (or 14.04.xx).
if [ "`lsb_release -d | sed 's/.*:\s*//' | sed 's/14\.04\.[0-9]/14.04/' `" != "Ubuntu 14.04 LTS" ]; then
	echo "Mail-in-a-Box only supports being installed on Ubuntu 14.04, sorry. You are running:"
	echo
	lsb_release -d | sed 's/.*:\s*//'
	echo
	echo "We can't write scripts that run on every possible setup, sorry."
	exit 1
fi

# Check that we have enough memory.
#
# /proc/meminfo reports free memory in kibibytes. Our baseline will be 768 KB,
# which is 750000 kibibytes.
#
# Skip the check if we appear to be running inside of Vagrant, because that's really just for testing.
TOTAL_PHYSICAL_MEM=$(head -n 1 /proc/meminfo | awk '{print $2}')
if [ $TOTAL_PHYSICAL_MEM -lt 750000 ]; then
if [ ! -d /vagrant ]; then
	TOTAL_PHYSICAL_MEM=$(expr \( \( $TOTAL_PHYSICAL_MEM \* 1024 \) / 1000 \) / 1000)
	echo "Your Mail-in-a-Box needs more memory (RAM) to function properly."
	echo "Please provision a machine with at least 768 MB, 1 GB recommended."
	echo "This machine has $TOTAL_PHYSICAL_MEM MB memory."
	exit 1
fi
fi
