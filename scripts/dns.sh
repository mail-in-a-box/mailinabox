# Configures a DNS server using nsd.
#
# After running this script, you also must run scripts/dns_update.sh,
# and any time a zone file is added/changed/removed. It should be
# run after DKIM is configured, however.

apt-get -qq -y install nsd3

if [ -z "$PUBLIC_HOSTNAME" ]; then
	PUBLIC_HOSTNAME=example.org
fi

if [ -z "$PUBLIC_IP" ]; then
	# works on EC2 only...
	PUBLIC_IP=`wget -q -O- http://instance-data/latest/meta-data/public-ipv4`
fi

sudo mkdir -p /var/run/nsd3
mkdir -p "$STORAGE_ROOT/dns";

# Store our desired IP address (to put in the zone files) for later.

echo $PUBLIC_IP > $STORAGE_ROOT/dns/our_ip

# Create the default zone if it doesn't exist.

if [ ! -f "$STORAGE_ROOT/dns/$PUBLIC_HOSTNAME.txt" ]; then
	# can be an empty file, defaults are applied elsewhere
	cat > "$STORAGE_ROOT/dns/$PUBLIC_HOSTNAME.txt" << EOF;
EOF
fi

chown -R ubuntu.ubuntu $STORAGE_ROOT/dns

ufw allow domain

