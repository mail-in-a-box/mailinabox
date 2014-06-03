# DNS: Configure a DNS server using nsd
#######################################

# After running this script, you also must run setup/dns_update.sh,
# and any time a zone file is added/changed/removed, and any time a
# new domain name becomes in use by a mail user.
#
# This script will turn on DNS for $PUBLIC_HOSTNAME.

source setup/functions.sh # load our functions

# Install nsd, our DNS server software.

# ...but first, we have to create the user because the 
# current Ubuntu forgets to do so in the .deb
# see issue #25 and https://bugs.launchpad.net/ubuntu/+source/nsd/+bug/1311886
if id nsd > /dev/null 2>&1; then
	true; #echo "nsd user exists... good";
else
	useradd nsd;
fi

# Okay now install the package.
# bc is needed by dns_update.

apt_install nsd bc

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

ufw_allow domain

