source /etc/mailinabox.conf
source setup/functions.sh # load our functions

# Basic System Configuration
# -------------------------

# ### Set hostname of the box

# If the hostname is not correctly resolvable sudo can't be used. This will result in
# errors during the install
#
# First set the hostname in the configuration file, then activate the setting

echo $PRIMARY_HOSTNAME > /etc/hostname
hostname $PRIMARY_HOSTNAME

# ### Fix permissions

# The default Ubuntu Bionic image on Scaleway throws warnings during setup about incorrect
# permissions (group writeable) set on the following directories.

chmod g-w /etc /etc/default /usr

# ### Add swap space to the system

# If the physical memory of the system is below 2GB it is wise to create a
# swap file. This will make the system more resiliant to memory spikes and
# prevent for instance spam filtering from crashing

# We will create a 1G file, this should be a good balance between disk usage
# and buffers for the system. We will only allocate this file if there is more
# than 5GB of disk space available

# The following checks are performed:
# - Check if swap is currently mountend by looking at /proc/swaps
# - Check if the user intents to activate swap on next boot by checking fstab entries.
# - Check if a swapfile already exists
# - Check if the root file system is not btrfs, might be an incompatible version with
#   swapfiles. User should hanle it them selves.
# - Check the memory requirements
# - Check available diskspace

# See https://www.digitalocean.com/community/tutorials/how-to-add-swap-on-ubuntu-14-04
# for reference

SWAP_MOUNTED=$(cat /proc/swaps | tail -n+2)
SWAP_IN_FSTAB=$(grep "swap" /etc/fstab || /bin/true)
ROOT_IS_BTRFS=$(grep "\/ .*btrfs" /proc/mounts || /bin/true)
TOTAL_PHYSICAL_MEM=$(head -n 1 /proc/meminfo | awk '{print $2}' || /bin/true)
AVAILABLE_DISK_SPACE=$(df / --output=avail | tail -n 1)
if
	[ -z "$SWAP_MOUNTED" ] &&
	[ -z "$SWAP_IN_FSTAB" ] &&
	[ ! -e /swapfile ] &&
	[ -z "$ROOT_IS_BTRFS" ] &&
	[ $TOTAL_PHYSICAL_MEM -lt 1900000 ] &&
	[ $AVAILABLE_DISK_SPACE -gt 5242880 ]
then
	echo "Adding a swap file to the system..."

	# Allocate and activate the swap file. Allocate in 1KB chuncks
	# doing it in one go, could fail on low memory systems
	dd if=/dev/zero of=/swapfile bs=1024 count=$[1024*1024] status=none
	if [ -e /swapfile ]; then
		chmod 600 /swapfile
		hide_output mkswap /swapfile
		swapon /swapfile
	fi

	# Check if swap is mounted then activate on boot
	if swapon -s | grep -q "\/swapfile"; then
		echo "/swapfile   none    swap    sw    0   0" >> /etc/fstab
	else
		echo "ERROR: Swap allocation failed"
	fi
fi

# ### Set log retention policy.

# Set the systemd journal log retention from infinite to 10 days,
# since over time the logs take up a large amount of space.
# (See https://discourse.mailinabox.email/t/journalctl-reclaim-space-on-small-mailinabox/6728/11.)
tools/editconf.py /etc/systemd/journald.conf MaxRetentionSec=10day

# ### Add PPAs.

# We install some non-standard Ubuntu packages maintained by other
# third-party providers. First ensure add-apt-repository is installed.

if [ ! -f /usr/bin/add-apt-repository ]; then
	echo "Installing add-apt-repository..."
	hide_output apt-get update
	apt_install software-properties-common
fi

# Ensure the universe repository is enabled since some of our packages
# come from there and minimal Ubuntu installs may have it turned off.
hide_output add-apt-repository -y universe

# Install the certbot PPA.
if [ $(. /etc/os-release; echo $VERSION_ID | awk -F. '{print $1}') -le 18 ]
then
    hide_output add-apt-repository -y ppa:certbot/certbot
else
    hide_output snap install core
    hide_output snap refresh core
    if ! snap list certbot 1>/dev/null 2>&1; then
        # a ppa was required on ubuntu 18, but snaps are used in ubuntu 19+
        # remove the ppa and certbot per eff's instructions
        hide_output add-apt-repository -r -y ppa:certbot/certbot
        hide_output apt-get remove -y certbot
    fi
    hide_output snap install --classic certbot
    ln -sf /snap/bin/certbot /usr/bin/certbot
fi

# Install the duplicity PPA.
hide_output add-apt-repository -y ppa:duplicity-team/duplicity-release-git

# ### Update Packages

# Update system packages to make sure we have the latest upstream versions
# of things from Ubuntu, as well as the directory of packages provide by the
# PPAs so we can install those packages later.

if [ "${SKIP_SYSTEM_UPDATE:-0}" != "1" ]; then
	echo Updating system packages...
	hide_output apt-get update
	apt_get_quiet upgrade

# Old kernels pile up over time and take up a lot of disk space, and because of Mail-in-a-Box
# changes there may be other packages that are no longer needed. Clear out anything apt knows
# is safe to delete.

	apt_get_quiet autoremove
fi

# ### Install System Packages

# Install basic utilities.
#
# * haveged: Provides extra entropy to /dev/random so it doesn't stall
#	         when generating random numbers for private keys (e.g. during
#	         ldns-keygen).
# * unattended-upgrades: Apt tool to install security updates automatically.
# * cron: Runs background processes periodically.
# * ntp: keeps the system time correct
# * fail2ban: scans log files for repeated failed login attempts and blocks the remote IP at the firewall
# * netcat-openbsd: `nc` command line networking tool
# * git: we install some things directly from github
# * sudo: allows privileged users to execute commands as root without being root
# * coreutils: includes `nproc` tool to report number of processors, mktemp
# * bc: allows us to do math to compute sane defaults
# * openssh-client: provides ssh-keygen

echo Installing system packages...
apt_install python3 python3-dev python3-pip python3-setuptools \
	netcat-openbsd wget curl git sudo coreutils bc \
	haveged pollinate openssh-client unzip \
	unattended-upgrades cron ntp fail2ban rsyslog

# ### Suppress Upgrade Prompts
# When Ubuntu 20 comes out, we don't want users to be prompted to upgrade,
# because we don't yet support it.
if [ -f /etc/update-manager/release-upgrades ]; then
	tools/editconf.py /etc/update-manager/release-upgrades Prompt=never
	rm -f /var/lib/ubuntu-release-upgrader/release-upgrade-available
fi

# ### Set the system timezone
#
# Some systems are missing /etc/timezone, which we cat into the configs for
# Z-Push and ownCloud, so we need to set it to something. Daily cron tasks
# like the system backup are run at a time tied to the system timezone, so
# letting the user choose will help us identify the right time to do those
# things (i.e. late at night in whatever timezone the user actually lives
# in).
#
# However, changing the timezone once it is set seems to confuse fail2ban
# and requires restarting fail2ban (done below in the fail2ban
# section) and syslog (see #328). There might be other issues, and it's
# not likely the user will want to change this, so we only ask on first
# setup.
if [ -z "${NONINTERACTIVE:-}" ]; then
	if [ ! -f /etc/timezone ] || [ ! -z ${FIRST_TIME_SETUP:-} ]; then
		# If the file is missing or this is the user's first time running
		# Mail-in-a-Box setup, run the interactive timezone configuration
		# tool.
		dpkg-reconfigure tzdata
		restart_service rsyslog
	fi
else
	# This is a non-interactive setup so we can't ask the user.
	# If /etc/timezone is missing, set it to UTC.
	if [ ! -f /etc/timezone ]; then
		echo "Setting timezone to UTC."
		echo "Etc/UTC" > /etc/timezone
		restart_service rsyslog
	fi
fi

# ### Seed /dev/urandom
#
# /dev/urandom is used by various components for generating random bytes for
# encryption keys and passwords:
#
# * TLS private key (see `ssl.sh`, which calls `openssl genrsa`)
# * DNSSEC signing keys (see `dns.sh`)
# * our management server's API key (via Python's os.urandom method)
# * Roundcube's SECRET_KEY (`webmail.sh`)
#
# Why /dev/urandom? It's the same as /dev/random, except that it doesn't wait
# for a constant new stream of entropy. In practice, we only need a little
# entropy at the start to get going. After that, we can safely pull a random
# stream from /dev/urandom and not worry about how much entropy has been
# added to the stream. (http://www.2uo.de/myths-about-urandom/) So we need
# to worry about /dev/urandom being seeded properly (which is also an issue
# for /dev/random), but after that /dev/urandom is superior to /dev/random
# because it's faster and doesn't block indefinitely to wait for hardware
# entropy. Note that `openssl genrsa` even uses `/dev/urandom`, and if it's
# good enough for generating an RSA private key, it's good enough for anything
# else we may need.
#
# Now about that seeding issue....
#
# /dev/urandom is seeded from "the uninitialized contents of the pool buffers when
# the kernel starts, the startup clock time in nanosecond resolution,...and
# entropy saved across boots to a local file" as well as the order of
# execution of concurrent accesses to /dev/urandom. (Heninger et al 2012,
# https://factorable.net/weakkeys12.conference.pdf) But when memory is zeroed,
# the system clock is reset on boot, /etc/init.d/urandom has not yet run, or
# the machine is single CPU or has no concurrent accesses to /dev/urandom prior
# to this point, /dev/urandom may not be seeded well. After this, /dev/urandom
# draws from the same entropy sources as /dev/random, but it doesn't block or
# issue any warnings if no entropy is actually available. (http://www.2uo.de/myths-about-urandom/)
# Entropy might not be readily available because this machine has no user input
# devices (common on servers!) and either no hard disk or not enough IO has
# ocurred yet --- although haveged tries to mitigate this. So there's a good chance
# that accessing /dev/urandom will not be drawing from any hardware entropy and under
# a perfect-storm circumstance where the other seeds are meaningless, /dev/urandom
# may not be seeded at all.
#
# The first thing we'll do is block until we can seed /dev/urandom with enough
# hardware entropy to get going, by drawing from /dev/random. haveged makes this
# less likely to stall for very long.

echo Initializing system random number generator...
dd if=/dev/random of=/dev/urandom bs=1 count=32 2> /dev/null

# This is supposedly sufficient. But because we're not sure if hardware entropy
# is really any good on virtualized systems, we'll also seed from Ubuntu's
# pollinate servers:

pollinate  -q -r

# Between these two, we really ought to be all set.

# We need an ssh key to store backups via rsync, if it doesn't exist create one
if [ ! -f /root/.ssh/id_rsa_miab ]; then
	echo 'Creating SSH key for backup…'
	ssh-keygen -t rsa -b 2048 -a 100 -f /root/.ssh/id_rsa_miab -N '' -q
fi

# ### Package maintenance
#
# Allow apt to install system updates automatically every day.

cat > /etc/apt/apt.conf.d/02periodic <<EOF;
APT::Periodic::MaxAge "7";
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Verbose "0";
EOF

# ### Firewall

# Various virtualized environments like Docker and some VPSs don't provide #NODOC
# a kernel that supports iptables. To avoid error-like output in these cases, #NODOC
# we skip this if the user sets DISABLE_FIREWALL=1. #NODOC
if [ -z "${DISABLE_FIREWALL:-}" ]; then
	# Install `ufw` which provides a simple firewall configuration.
	apt_install ufw

	# Allow incoming connections to SSH.
	ufw_limit ssh;

	# ssh might be running on an alternate port. Use sshd -T to dump sshd's #NODOC
	# settings, find the port it is supposedly running on, and open that port #NODOC
	# too. #NODOC
	SSH_PORT=$(sshd -T 2>/dev/null | grep "^port " | sed "s/port //") #NODOC
	if [ ! -z "$SSH_PORT" ]; then
	if [ "$SSH_PORT" != "22" ]; then

	echo Opening alternate SSH port $SSH_PORT. #NODOC
	ufw_limit $SSH_PORT #NODOC

	fi
	fi

	ufw --force enable;
fi #NODOC

# ### Local DNS Service

# Install a local recursive DNS server --- i.e. for DNS queries made by
# local services running on this machine.
#
# (This is unrelated to the box's public, non-recursive DNS server that
# answers remote queries about domain names hosted on this box. For that
# see dns.sh.)
#
# The default systemd-resolved service provides local DNS name resolution. By default it
# is a recursive stub nameserver, which means it simply relays requests to an
# external nameserver, usually provided by your ISP or configured in /etc/systemd/resolved.conf.
#
# This won't work for us for three reasons.
#
# 1) We have higher security goals --- we want DNSSEC to be enforced on all
#    DNS queries (some upstream DNS servers do, some don't).
# 2) We will configure postfix to use DANE, which uses DNSSEC to find TLS
#    certificates for remote servers. DNSSEC validation *must* be performed
#    locally because we can't trust an unencrypted connection to an external
#    DNS server.
# 3) DNS-based mail server blacklists (RBLs) typically block large ISP
#    DNS servers because they only provide free data to small users. Since
#    we use RBLs to block incoming mail from blacklisted IP addresses,
#    we have to run our own DNS server. See #1424.
#
# systemd-resolved has a setting to perform local DNSSEC validation on all
# requests (in /etc/systemd/resolved.conf, set DNSSEC=yes), but because it's
# a stub server the main part of a request still goes through an upstream
# DNS server, which won't work for RBLs. So we really need a local recursive
# nameserver.
#
# We'll install `bind9`, which as packaged for Ubuntu, has DNSSEC enabled by default via "dnssec-validation auto".
# We'll have it be bound to 127.0.0.1 so that it does not interfere with
# the public, recursive nameserver `nsd` bound to the public ethernet interfaces.
#
# About the settings:
#
# * Adding -4 to OPTIONS will have `bind9` not listen on IPv6 addresses
#   so that we're sure there's no conflict with nsd, our public domain
#   name server, on IPV6.
# * The listen-on directive in named.conf.options restricts `bind9` to
#   binding to the loopback interface instead of all interfaces.
# * The max-recursion-queries directive increases the maximum number of iterative queries.
#  	If more queries than specified are sent, bind9 returns SERVFAIL. After flushing the cache during system checks,
#	we ran into the limit thus we are increasing it from 75 (default value) to 100.
apt_install bind9
tools/editconf.py /etc/default/bind9 \
	"OPTIONS=\"-u bind -4\""
if ! grep -q "listen-on " /etc/bind/named.conf.options; then
	# Add a listen-on directive if it doesn't exist inside the options block.
	sed -i "s/^}/\n\tlisten-on { 127.0.0.1; };\n}/" /etc/bind/named.conf.options
fi
if ! grep -q "max-recursion-queries " /etc/bind/named.conf.options; then
	# Add a max-recursion-queries directive if it doesn't exist inside the options block.
	sed -i "s/^}/\n\tmax-recursion-queries 100;\n}/" /etc/bind/named.conf.options
fi

# First we'll disable systemd-resolved's management of resolv.conf and its stub server.
# Breaking the symlink to /run/systemd/resolve/stub-resolv.conf means
# systemd-resolved will read it for DNS servers to use. Put in 127.0.0.1,
# which is where bind9 will be running. Obviously don't do this before
# installing bind9 or else apt won't be able to resolve a server to
# download bind9 from.
rm -f /etc/resolv.conf
tools/editconf.py /etc/systemd/resolved.conf DNSStubListener=no
echo "nameserver 127.0.0.1" > /etc/resolv.conf

# Restart the DNS services.

restart_service bind9
systemctl restart systemd-resolved

# ### Fail2Ban Service

# Configure the Fail2Ban installation to prevent dumb bruce-force attacks against dovecot, postfix, ssh, etc.
rm -f /etc/fail2ban/jail.local # we used to use this file but don't anymore
rm -f /etc/fail2ban/jail.d/defaults-debian.conf # removes default config so we can manage all of fail2ban rules in one config
cat conf/fail2ban/jails.conf \
    | sed "s/PUBLIC_IPV6/$PUBLIC_IPV6/g" \
	| sed "s/PUBLIC_IP/$PUBLIC_IP/g" \
	| sed "s#STORAGE_ROOT#$STORAGE_ROOT#" \
	> /etc/fail2ban/jail.d/mailinabox.conf
cp -f conf/fail2ban/filter.d/* /etc/fail2ban/filter.d/

# On first installation, the log files that the jails look at don't all exist.
# e.g., The roundcube error log isn't normally created until someone logs into
# Roundcube for the first time. This causes fail2ban to fail to start. Later
# scripts will ensure the files exist and then fail2ban is given another
# restart at the very end of setup.
restart_service fail2ban
