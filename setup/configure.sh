#!/bin/bash

source setup/functions.sh # load our functions

# Ask the user for the PRIMARY_HOSTNAME, PUBLIC_IP, PUBLIC_IPV6, and CSR_COUNTRY
# if values have not already been set in environment variables. When running
# non-interactively, be sure to set values for all!
source setup/questions.sh

# Automatic configuration, e.g. as used in our Vagrant configuration.
if [ "$PUBLIC_IP" = "auto" ]; then
	# Use a public API to get our public IP address, or fall back to local network configuration.
	PUBLIC_IP=$(get_publicip_from_web_service 4 || get_default_privateip 4)
fi
if [ "$PUBLIC_IPV6" = "auto" ]; then
	# Use a public API to get our public IPv6 address, or fall back to local network configuration.
	PUBLIC_IPV6=$(get_publicip_from_web_service 6 || get_default_privateip 6)
fi
if [ "$PRIMARY_HOSTNAME" = "auto" ]; then
	# Use reverse DNS to get this machine's hostname. Install bind9-host early.
	hide_output apt-get -y install bind9-host
	PRIMARY_HOSTNAME=$(get_default_hostname)
elif [ "$PRIMARY_HOSTNAME" = "auto-easy" ]; then
	# Generate a probably-unique subdomain under our justtesting.email domain.
	PRIMARY_HOSTNAME=`echo $PUBLIC_IP | sha1sum | cut -c1-5`.justtesting.email
fi

# Show the configuration, since the user may have not entered it manually.
echo
echo "Primary Hostname: $PRIMARY_HOSTNAME"
echo "Public IP Address: $PUBLIC_IP"
if [ ! -z "$PUBLIC_IPV6" ]; then
	echo "Public IPv6 Address: $PUBLIC_IPV6"
fi
if [ "$PRIVATE_IP" != "$PUBLIC_IP" ]; then
	echo "Private IP Address: $PRIVATE_IP"
fi
if [ "$PRIVATE_IPV6" != "$PUBLIC_IPV6" ]; then
	echo "Private IPv6 Address: $PRIVATE_IPV6"
fi
if [ -f /usr/bin/git ]; then
	echo "Mail-in-a-Box Version: " $(git describe)
fi
echo

# Run some network checks to make sure setup on this machine makes sense.
if [ -z "$SKIP_NETWORK_CHECKS" ]; then
	. setup/network-checks.sh
fi

# For the first time (if the config file (/etc/mailinabox.conf) not exists):
# Create the user named "user-data" and store all persistent user
# data (mailboxes, etc.) in that user's home directory.
#
# If the config file exists:
# Apply the existing configuration options for STORAGE_USER/ROOT
if [ -z "$STORAGE_USER" ]; then
	STORAGE_USER=$([[ -z "$DEFAULT_STORAGE_USER" ]] && echo "user-data" || echo "$DEFAULT_STORAGE_USER")
fi

if [ -z "$STORAGE_ROOT" ]; then
	STORAGE_ROOT=$([[ -z "$DEFAULT_STORAGE_ROOT" ]] && echo "/home/$STORAGE_USER" || echo "$DEFAULT_STORAGE_ROOT")
fi

# Create the STORAGE_USER if it not exists
if ! id -u $STORAGE_USER >/dev/null 2>&1; then
	useradd -m $STORAGE_USER
fi

# Create the STORAGE_ROOT if it not exists
if [ ! -d $STORAGE_ROOT ]; then
	mkdir -p $STORAGE_ROOT
fi

# Create mailinabox.version file if not exists
if [ ! -f $STORAGE_ROOT/mailinabox.version ]; then
	echo $(setup/migrate.py --current) > $STORAGE_ROOT/mailinabox.version
	chown $STORAGE_USER:$STORAGE_USER $STORAGE_ROOT/mailinabox.version
fi


# Save the global options in /etc/mailinabox.conf so that standalone
# tools know where to look for data.
cat > /etc/mailinabox.conf << EOF;
STORAGE_USER=$STORAGE_USER
STORAGE_ROOT=$STORAGE_ROOT
PRIMARY_HOSTNAME=$PRIMARY_HOSTNAME
PUBLIC_IP=$PUBLIC_IP
PUBLIC_IPV6=$PUBLIC_IPV6
PRIVATE_IP=$PRIVATE_IP
PRIVATE_IPV6=$PRIVATE_IPV6
CSR_COUNTRY=$CSR_COUNTRY
EOF
