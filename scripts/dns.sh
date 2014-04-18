# DNS: Configure a DNS server using nsd
#######################################

# After running this script, you also must run scripts/dns_update.sh,
# and any time a zone file is added/changed/removed, and any time a
# new domain name becomes in use by a mail user.
#
# This script will turn on DNS for $PUBLIC_HOSTNAME.

# Install nsd, our DNS server software.

apt-get -qq -y install nsd

# Prepare nsd's configuration.

sudo mkdir -p /var/run/nsd
mkdir -p "$STORAGE_ROOT/dns";

# Create the default zone if it doesn't exist.

if [ ! -f "$STORAGE_ROOT/dns/$PUBLIC_HOSTNAME.txt" ]; then
	# can be an empty file, defaults are applied elsewhere
	cat > "$STORAGE_ROOT/dns/$PUBLIC_HOSTNAME.txt" << EOF;
EOF
fi

# Let the storage user own all DNS configuration files.

chown -R $STORAGE_USER.$STORAGE_USER $STORAGE_ROOT/dns

# Permit DNS queries on TCP/UDP in the firewall.

ufw allow domain

