# Are we running as root?
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root. Please re-run like this:" >&2
	echo >&2
	echo "sudo $0" >&2
	echo >&2
	exit 1
fi

# Check if on Linux
if ! echo "$OSTYPE" | grep -iq "linux"; then
	echo "Error: This script must be run on Linux." >&2
	exit 1
fi

. /etc/os-release

# Check that we are running on Ubuntu 14.04 LTS (or 14.04.xx).
if ! echo "$ID" | grep -iq "ubuntu" || ! echo "$VERSION_ID" | grep -iq "14.04"; then
	if echo "$ID" | grep -iq "ubuntu" && echo "$VERSION_ID" | grep -iq "18.04"; then
		echo "Ubuntu 18.04 is not yet fully supported, but is available for testing at: https://github.com/mail-in-a-box/mailinabox/tree/ubuntu_bionic" >&2
		exit 1
	else
		echo "Mail-in-a-Box only supports being installed on Ubuntu 14.04, sorry. You are running:" >&2
		echo >&2
		echo "${PRETTY_NAME:-$ID-$VERSION_ID}" >&2
		echo >&2
		echo "We can't write scripts that run on every possible setup, sorry." >&2
		exit 1
	fi
fi

# Check for the Windows Subsystem for Linux (WSL)
if uname -r | grep -iq "microsoft"; then
	echo "Warning: The Windows Subsystem for Linux (WSL) is not yet fully supported by this script."
fi

# Check that we have enough memory.
#
# /proc/meminfo reports free memory in kibibytes. Our baseline will be 512 MB,
# which is 500000 kibibytes.
#
# We will display a warning if the memory is below 768 MB which is 750000 kibibytes
#
# Skip the check if we appear to be running inside of Vagrant, because that's really just for testing.
TOTAL_PHYSICAL_MEM=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
TOTAL_SWAP=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)
if [ "$TOTAL_PHYSICAL_MEM" -lt 500000 ]; then
	if [ ! -d /vagrant ]; then
		echo "Your Mail-in-a-Box needs more memory (RAM) to function properly." >&2
		echo "Please provision a machine with at least 512 MB, 1 GB (1024 MB) recommended." >&2
		echo "This machine has $(printf "%'d" $((((TOTAL_PHYSICAL_MEM * 1024) / 1000) / 1000))) MB ($(printf "%'d" $((TOTAL_PHYSICAL_MEM / 1024))) MiB) memory."
		exit 1
	fi
fi
if [ "$TOTAL_PHYSICAL_MEM" -lt 750000 ]; then
	echo "WARNING: Your Mail-in-a-Box has less than 768 MB of memory."
	echo "         It might run unreliably when under heavy load."
fi

# Check connectivity
if ! ping -q -c 3 mailinabox.email > /dev/null 2>&1; then
	echo "Error: Could not reach mailinabox.email, please check your internet connection and run this script again." >&2
	exit 1
fi

# Check that tempfs is mounted with exec
MOUNTED_TMP_AS_NO_EXEC=$(grep "/tmp.*noexec" /proc/mounts)
if [ -n "$MOUNTED_TMP_AS_NO_EXEC" ]; then
	echo "Mail-in-a-Box has to have exec rights on /tmp, please mount /tmp with exec" >&2
	exit 1
fi

# Check that no .wgetrc exists
if [ -e ~/.wgetrc ]; then
	echo "Mail-in-a-Box expects no overrides to wget defaults, ~/.wgetrc exists" >&2
	exit 1
fi

# Check that we are running on x86_64 or i686, any other architecture is unsupported and
# will fail later in the setup when we try to install the custom build lucene packages.
#
# Set ARM=1 to ignore this check if you have built the packages yourself. If you do this
# you are on your own!
ARCHITECTURE=$(getconf LONG_BIT)
if [ "$HOSTTYPE" != "x86_64" ] && [ "$HOSTTYPE" != "i686" ]; then
	if [ -z "$ARM" ]; then
		echo "Mail-in-a-Box only supports x86_64 or i686 and will not work on any other architecture, like ARM." >&2
		echo "Your architecture is $HOSTTYPE ($ARCHITECTURE-bit)"
		exit 1
	fi
fi
