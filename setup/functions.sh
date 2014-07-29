function hide_output {
	# This function hides the output of a command unless the command fails
	# and returns a non-zero exit code.

	# Get a temporary file.
	OUTPUT=$(tempfile)

	# Execute command, redirecting stderr/stdout to the temporary file.
	$@ &> $OUTPUT

	# If the command failed, show the output that was captured in the temporary file.
	if [ $? != 0 ]; then
		# Something failed.
		echo
		echo FAILED: $@
		echo -----------------------------------------
		cat $OUTPUT
		echo -----------------------------------------
	fi

	# Remove temporary file.
	rm -f $OUTPUT
}

function apt_install {
	# Report any packages already installed.
	PACKAGES=$@
	TO_INSTALL=""
	ALREADY_INSTALLED=""
	for pkg in $PACKAGES; do
		if dpkg -s $pkg 2>/dev/null | grep "^Status: install ok installed" > /dev/null; then
			if [[ ! -z "$ALREADY_INSTALLED" ]]; then ALREADY_INSTALLED="$ALREADY_INSTALLED, "; fi
			ALREADY_INSTALLED="$ALREADY_INSTALLED$pkg (`dpkg -s $pkg | grep ^Version: | sed -e 's/.*: //'`)"
		else
			TO_INSTALL="$TO_INSTALL""$pkg "
		fi
	done

	# List the packages already installed.
	if [[ ! -z "$ALREADY_INSTALLED" ]]; then
		echo already installed: $ALREADY_INSTALLED
	fi

	# List the packages about to be installed.
	if [[ ! -z "$TO_INSTALL" ]]; then
		echo installing $TO_INSTALL...
	fi

	# 'DEBIAN_FRONTEND=noninteractive' is to prevent dbconfig-common from asking you questions.
	#
	# Although we could pass -qq to apt-get to make output quieter, many packages write to stdout
	# and stderr things that aren't really important. Use our hide_output function to capture
	# all of that and only show it if there is a problem (i.e. if apt_get returns a failure exit status).
	#
	# Also note that we still include the whole original package list in the apt-get command in
	# case it wants to upgrade anything, I guess? Maybe we can remove it. Doesn't normally make
	# a difference.
	DEBIAN_FRONTEND=noninteractive \
	hide_output \
	apt-get -y install $PACKAGES
}

function get_default_hostname {
	# Guess the machine's hostname. It should be a fully qualified
	# domain name suitable for DNS. None of these calls may provide
	# the right value, but it's the best guess we can make.
	set -- $(hostname --fqdn      2>/dev/null ||
                 hostname --all-fqdns 2>/dev/null ||
                 hostname             2>/dev/null)
	printf '%s\n' "$1" # return this value
}

function get_default_publicip {
	# Get the machine's public IP address. The machine might have
	# an IP on a private network, but the IP address that we put
	# into DNS must be one on the public Internet. Try a public
	# API, but if that fails (maybe we don't have Internet access
	# right now) then use the IP address that this machine knows
	# itself as.
	get_publicip_from_web_service 4 || get_default_privateip 4
}

function get_default_publicipv6 {
	get_publicip_from_web_service 6 || get_default_privateip 6
}

function get_publicip_from_web_service {
	# This seems to be the most reliable way to determine the
	# machine's public IP address: asking a very nice web API
	# for how they see us. Thanks go out to icanhazip.com.
	# See: https://major.io/icanhazip-com-faq/
	#
	# Pass '4' or '6' as an argument to this function to specify
	# what type of address to get (IPv4, IPv6).
	curl -$1 --fail --silent icanhazip.com 2>/dev/null
}

function get_default_privateip {
	# Return the IP address of the network interface connected
	# to the Internet.
	#
	# We used to use `hostname -I` and then filter for either
	# IPv4 or IPv6 addresses. However if there are multiple
	# network interfaces on the machine, not all may be for
	# reaching the Internet.
	#
	# Instead use `ip route get` which asks the kernel to use
	# the system's routes to select which interface would be
	# used to reach a public address. We'll use 8.8.8.8 as
	# the destination. It happens to be Google Public DNS, but
	# no connection is made. We're just seeing how the box
	# would connect to it. There many be multiple IP addresses
	# assigned to an interface. `ip route get` reports the
	# preferred. That's good enough for us. See issue #121.
	#
	# Also see ae67409603c49b7fa73c227449264ddd10aae6a9 and
	# issue #3 for why/how we originally added IPv6.
	#
	# Pass '4' or '6' as an argument to this function to specify
	# what type of address to get (IPv4, IPv6).

	target=8.8.8.8

	# For the IPv6 route, use the corresponding IPv6 address
	# of Google Public DNS. Again, it doesn't matter so long
	# as it's an address on the public Internet.
	if [ "$1" == "6" ]; then target=2001:4860:4860::8888; fi

	ip -$1 -o route get $target \
		| grep -v unreachable \
		| sed "s/.* src \([^ ]*\).*/\1/"
}

function ufw_allow {
	if [ -z "$DISABLE_FIREWALL" ]; then
		# ufw has completely unhelpful output
		ufw allow $1 > /dev/null;
	fi
}

function restart_service {
	hide_output service $1 restart
}
