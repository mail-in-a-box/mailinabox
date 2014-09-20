source setup/functions.sh # load our functions

# Base system configuration.

echo Updating system packages...
hide_output apt-get update
hide_output apt-get -y upgrade

# Install basic utilities.
#
#	haveged: Provides extra entropy to /dev/random so it doesn't stall
#	         when generating random numbers for private keys (e.g. during
#	         ldns-keygen).
#	unattended-upgrades: Apt tool to install security updates automatically.
#   	ntp: keeps the system time correct
#   	fail2ban: scans log files for repeated failed login attempts and blocks the remote IP at the firewall

apt_install python3 python3-dev python3-pip \
	wget curl \
	haveged unattended-upgrades ntp fail2ban

# Allow apt to install system updates automatically every day.

cat > /etc/apt/apt.conf.d/02periodic <<EOF;
APT::Periodic::MaxAge "7";
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Verbose "1";
EOF

if [ -z "$DISABLE_FIREWALL" ]; then
	# Turn on the firewall. First allow incoming SSH, then turn on the firewall.
	# Other ports will be opened at the point where we set up those services.
	#
	# Various virtualized environments like Docker and some VPSs don't provide
	# a kernel that supports iptables. To avoid error-like output in these cases,
	# let us disable the firewall.

	apt_install ufw

	ufw_allow ssh;

	# ssh might be running on an alternate port. Use sshd -T to dump sshd's
	# settings, find the port it is supposedly running on, and open that port
	# too.
	SSH_PORT=$(sshd -T 2>/dev/null | grep "^port " | sed "s/port //")
	if [ ! -z "$SSH_PORT" ]; then
		if [ "$SSH_PORT" != "22" ]; then
			echo Opening alternate SSH port $SSH_PORT.
			ufw_allow $SSH_PORT;
		fi
	fi

	ufw --force enable;
fi

# Resolve DNS using bind9 locally, rather than whatever DNS server is supplied
# by the machine's network configuration. We do this to ensure that DNS queries
# that *we* make (i.e. looking up other external domains) perform DNSSEC checks.
# We could use Google's Public DNS, but we don't want to create a dependency on
# Google per our goals of decentralization. bind9, as packaged for Ubuntu, has
# DNSSEC enabled by default via "dnssec-validation auto".
#
# So we'll be running bind9 bound to 127.0.0.1 for locally-issued DNS queries
# and nsd bound to the public ethernet interface for remote DNS queries asking
# about our domain names. nsd is configured in dns.sh.
#
# About the settings:
#
# * RESOLVCONF=yes will have bind9 take over /etc/resolv.conf to tell
#   local services that DNS queries are handled on localhost.
# * Adding -4 to OPTIONS will have bind9 not listen on IPv6 addresses
#   so that we're sure there's no conflict with nsd, our public domain
#   name server, on IPV6.
# * The listen-on directive in named.conf.options restricts bind9 to
#   binding to the loopback interface instead of all interfaces.
apt_install bind9 resolvconf
tools/editconf.py /etc/default/bind9 \
	RESOLVCONF=yes \
	"OPTIONS=\"-u bind -4\""
if ! grep -q "listen-on " /etc/bind/named.conf.options; then
	# Add a listen-on directive if it doesn't exist inside the options block.
	sed -i "s/^}/\n\tlisten-on { 127.0.0.1; };\n}/" /etc/bind/named.conf.options
fi
if [ -f /etc/resolvconf/resolv.conf.d/original ]; then
	echo "Archiving old resolv.conf (was /etc/resolvconf/resolv.conf.d/original, now /etc/resolvconf/resolv.conf.original)."
	mv /etc/resolvconf/resolv.conf.d/original /etc/resolvconf/resolv.conf.original
fi

restart_service bind9
restart_service resolvconf
