# DNS: Configure a DNS server using nsd
#######################################

# This script installs packages, but the DNS zone files are only
# created by the /dns/update API in the management server because
# the set of zones (domains) hosted by the server depends on the
# mail users & aliases created by the user later.

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

# Okay now install the packages.

apt_install nsd

# Prepare nsd's configuration.

sudo mkdir -p /var/run/nsd

# Permit DNS queries on TCP/UDP in the firewall.

ufw_allow domain

