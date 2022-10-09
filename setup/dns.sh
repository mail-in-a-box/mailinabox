#!/bin/bash
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####

# DNS
# -----------------------------------------------

# This script installs packages, but the DNS zone files are only
# created by the /dns/update API in the management server because
# the set of zones (domains) hosted by the server depends on the
# mail users & aliases created by the user later.

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

# Prepare nsd's configuration.
# We configure nsd before installation as we only want it to bind to some addresses
# and it otherwise will have port / bind conflicts with bind9 used as the local resolver
mkdir -p /var/run/nsd
mkdir -p /etc/nsd
mkdir -p /etc/nsd/zones
touch /etc/nsd/zones.conf

cat > /etc/nsd/nsd.conf << EOF;
# Do not edit. Overwritten by Mail-in-a-Box setup.
server:
  hide-version: yes
  log-only-syslog: yes

  # identify the server (CH TXT ID.SERVER entry).
  identity: ""

  # The directory for zonefile: files.
  zonesdir: "/etc/nsd/zones"

  # Allows NSD to bind to IP addresses that are not (yet) added to the
  # network interface. This allows nsd to start even if the network stack
  # isn't fully ready, which apparently happens in some cases.
  # See https://www.nlnetlabs.nl/projects/nsd/nsd.conf.5.html.
  ip-transparent: yes

EOF

# nsd.log must exist or rsyslog won't write to it
if [ ! -e /var/log/nsd.log ]; then
    touch /var/log/nsd.log
    chown syslog:adm /var/log/nsd.log
fi

# Since we have bind9 listening on localhost for locally-generated
# DNS queries that require a recursive nameserver, and the system
# might have other network interfaces for e.g. tunnelling, we have
# to be specific about the network interfaces that nsd binds to.
for ip in $PRIVATE_IP $PRIVATE_IPV6; do
	echo "  ip-address: $ip" >> /etc/nsd/nsd.conf;
done

# nsd fails to start when ipv6 is disabled by the kernel on certain
# interfaces without "do-ip6" set to "no" and "control-enable" to "no"
# [confirm]. Even though the nsd docs say the default value for
# control-enable is no, running "nsd-checkconf -o control-enable
# /etc/nsd/nsd.conf" returns "yes", so we explicitly set it here.
#
# For instance, on Travis-CI, ipv6 is disabled on the lo and docker
# interfaces, but enabled on the primary interface ens4. nsd fails to
# start without these additions.
if kernel_ipv6_lo_disabled; then
    cat >> /etc/nsd/nsd.conf <<EOF
  do-ip4: yes
  do-ip6: no
remote-control:
  control-enable: no
EOF
fi

# Create a directory for additional configuration directives, including
# the zones.conf file written out by our management daemon.
echo "include: /etc/nsd/nsd.conf.d/*.conf" >> /etc/nsd/nsd.conf;

# Remove the old location of zones.conf that we generate. It will
# now be stored in /etc/nsd/nsd.conf.d.
rm -f /etc/nsd/zones.conf

# Add log rotation
cat > /etc/logrotate.d/nsd <<EOF;
/var/log/nsd.log {
  weekly
  missingok
  rotate 12
  compress
  delaycompress
  notifempty
}
EOF

# Install the packages.
#
# * nsd: The non-recursive nameserver that publishes our DNS records.
# * ldnsutils: Helper utilities for signing DNSSEC zones.
# * openssh-client: Provides ssh-keyscan which we use to create SSHFP records.
echo "Installing nsd (DNS server)..."
apt_install nsd ldnsutils openssh-client

# Make sure nsd is running and has the latest configuration
restart_service nsd

# Create DNSSEC signing keys.

mkdir -p "$STORAGE_ROOT/dns/dnssec";

# TLDs, registrars, and validating nameservers don't all support the same algorithms,
# so we'll generate keys using a few different algorithms so that dns_update.py can
# choose which algorithm to use when generating the zonefiles. See #1953 for recent
# discussion. File for previously used algorithms (i.e. RSASHA1-NSEC3-SHA1) may still
# be in the output directory, and we'll continue to support signing zones with them
# so that trust isn't broken with deployed DS records, but we won't generate those
# keys on new systems.
FIRST=1 #NODOC
for algo in RSASHA256 ECDSAP256SHA256; do
if [ ! -f "$STORAGE_ROOT/dns/dnssec/$algo.conf" ]; then
	if [ $FIRST == 1 ]; then
		echo "Generating DNSSEC signing keys..."
		FIRST=0 #NODOC
	fi

	# Create the Key-Signing Key (KSK) (with `-k`) which is the so-called
	# Secure Entry Point. The domain name we provide ("_domain_") doesn't
	# matter -- we'll use the same keys for all our domains.
	#
	# `ldns-keygen` outputs the new key's filename to stdout, which
	# we're capturing into the `KSK` variable.
	#
	# ldns-keygen uses /dev/random for generating random numbers by default.
	# This is slow and unecessary if we ensure /dev/urandom is seeded properly,
	# so we use /dev/urandom. See system.sh for an explanation. See #596, #115.
	# (This previously used -b 2048 but it's unclear if this setting makes sense
	# for non-RSA keys, so it's removed. The RSA-based keys are not recommended
	# anymore anyway.)
	KSK=$(umask 077; cd $STORAGE_ROOT/dns/dnssec; ldns-keygen -r /dev/urandom -a $algo -k _domain_);

	# Now create a Zone-Signing Key (ZSK) which is expected to be
	# rotated more often than a KSK, although we have no plans to
	# rotate it (and doing so would be difficult to do without
	# disturbing DNS availability.) Omit `-k`.
	# (This previously used -b 1024 but it's unclear if this setting makes sense
	# for non-RSA keys, so it's removed.)
	ZSK=$(umask 077; cd $STORAGE_ROOT/dns/dnssec; ldns-keygen -r /dev/urandom -a $algo _domain_);

	# These generate two sets of files like:
	#
	# * `K_domain_.+007+08882.ds`: DS record normally provided to domain name registrar (but it's actually invalid with `_domain_` so we don't use this file)
	# * `K_domain_.+007+08882.key`: public key
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

	# And loop to do the next algorithm...
done

# Force the dns_update script to be run every day to re-sign zones for DNSSEC
# before they expire. When we sign zones (in `dns_update.py`) we specify a
# 30-day validation window, so we had better re-sign before then.
cat > /etc/cron.daily/mailinabox-dnssec << EOF;
#!/bin/bash
# Mail-in-a-Box
# Re-sign any DNS zones with DNSSEC because the signatures expire periodically.
$(pwd)/tools/dns_update
EOF
chmod +x /etc/cron.daily/mailinabox-dnssec

# Permit DNS queries on TCP/UDP in the firewall.

ufw_allow domain

