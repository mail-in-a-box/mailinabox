#!/bin/bash
# DNS: Configure a DNS server to host our own DNS
# -----------------------------------------------

# This script installs packages, but the DNS zone files are only
# created by the /dns/update API in the management server because
# the set of zones (domains) hosted by the server depends on the
# mail users & aliases created by the user later.

source setup/functions.sh # load our functions

# Install `nsd`, our DNS server software, and `ldnsutils` which helps
# us sign zones for DNSSEC.

# ...but first, we have to create the user because the 
# current Ubuntu forgets to do so in the .deb
# see issue #25 and https://bugs.launchpad.net/ubuntu/+source/nsd/+bug/1311886
if id nsd > /dev/null 2>&1; then
	true; #echo "nsd user exists... good"; #NODOC
else
	useradd nsd;
fi

# Okay now install the packages.
#
# * nsd: The non-recursive nameserver that publishes our DNS records.
# * ldnsutils: Helper utilities for signing DNSSEC zones.
# * openssh-client: Provides ssh-keyscan which we use to create SSHFP records.

apt_install nsd ldnsutils openssh-client

# Prepare nsd's configuration.

mkdir -p /var/run/nsd

# Create DNSSEC signing keys.

mkdir -p "$STORAGE_ROOT/dns/dnssec";

# TLDs don't all support the same algorithms, so we'll generate keys using a few
# different algorithms.
#
# Supports RSASHA1-NSEC3-SHA1 (didn't test with RSASHA256):
#   .info and .me.
#
# Requires RSASHA256
#   .email
FIRST=1
for algo in RSASHA1-NSEC3-SHA1 RSASHA256; do
if [ ! -f "$STORAGE_ROOT/dns/dnssec/$algo.conf" ]; then
	if [ $FIRST == 1 ]; then
		echo "Generating DNSSEC signing keys. This may take a few minutes..."
		FIRST=0
	fi

	# Create the Key-Signing Key (KSK) (-k) which is the so-called
	# Secure Entry Point. Use a NSEC3-compatible algorithm (best
	# practice), and a nice and long keylength. The domain name we
	# provide ("_domain_") doesn't matter -- we'll use the same
	# keys for all our domains.
	KSK=$(umask 077; cd $STORAGE_ROOT/dns/dnssec; ldns-keygen -a $algo -b 2048 -k _domain_);

	# Now create a Zone-Signing Key (ZSK) which is expected to be
	# rotated more often than a KSK, although we have no plans to
	# rotate it (and doing so would be difficult to do without
	# disturbing DNS availability.) Omit '-k' and use a shorter key.
	ZSK=$(umask 077; cd $STORAGE_ROOT/dns/dnssec; ldns-keygen -a $algo -b 1024 _domain_);

	# These generate two sets of files like:
	#
	# * `K_domain_.+007+08882.ds`: DS record normally provided to domain name registrar (but it's actually invalid with "_domain_")
	# * `K_domain_.+007+08882.key`: public key (goes into DS record & upstream DNS provider like your registrar)
	# * `K_domain_.+007+08882.private`: private key (secret!)

	# The filenames are unpredictable and encode the key generation
	# options. So we'll store the names of the files we just generated.
	# We might have multiple keys down the road. This will identify
	# what keys are the current keys.
	cat > $STORAGE_ROOT/dns/dnssec/$algo.conf << EOF;
KSK=$KSK
ZSK=$ZSK
EOF
fi
done

# Force the dns_update script to be run every day to re-sign zones for DNSSEC.
cat > /etc/cron.daily/mailinabox-dnssec << EOF;
#!/bin/bash
# Mail-in-a-Box
# Re-sign any DNS zones with DNSSEC because the signatures expire periodically.
`pwd`/tools/dns_update
EOF
chmod +x /etc/cron.daily/mailinabox-dnssec

# Permit DNS queries on TCP/UDP in the firewall.

ufw_allow domain

