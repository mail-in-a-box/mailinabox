# DNS: Configure a DNS server using nsd
#######################################

# After running this script, you also must run scripts/dns_update.sh,
# and any time a zone file is added/changed/removed, and any time a
# new domain name becomes in use by a mail user.
#
# This script will turn on DNS for $PUBLIC_HOSTNAME.

# Install nsd3, our DNS server software.

apt-get -qq -y install nsd3

# Get configuraton information.

if [ -z "$PUBLIC_HOSTNAME" ]; then
	PUBLIC_HOSTNAME=example.org
fi

if [ -z "$PUBLIC_IP" ]; then
	# works on EC2 only...
	PUBLIC_IP=`wget -q -O- http://instance-data/latest/meta-data/public-ipv4`
fi

# Prepare nsd3's configuration.

sudo mkdir -p /var/run/nsd3
mkdir -p "$STORAGE_ROOT/dns";

# Store our desired IP address (to put in the zone files) for later.
# Also store our primary hostname, which we'll use for all DKIM signatures
# in case the user is only delegating MX and we aren't setting DKIM on
# the main DNS.

echo $PUBLIC_IP > $STORAGE_ROOT/dns/our_ip
echo $PUBLIC_HOSTNAME > $STORAGE_ROOT/dns/primary_hostname

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

