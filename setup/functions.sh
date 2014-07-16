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
	# Although we could pass -qq to apt-get to make output quieter, many packages write to stdout
	# and stderr things that aren't really important. Use our hide_output function to capture
	# all of that and only show it if there is a problem (i.e. if apt_get returns a failure exit status).
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
	get_publicip_from_web_service || get_publicip_fallback
}

function get_default_publicipv6 {
	get_publicipv6_from_web_service || get_publicipv6_fallback
}

function get_publicip_from_web_service {
	# This seems to be the most reliable way to determine the
	# machine's public IP address: asking a very nice web API
	# for how they see us. Thanks go out to icanhazip.com.
	curl -4 --fail --silent icanhazip.com 2>/dev/null
}

function get_publicipv6_from_web_service {
	curl -6 --fail --silent icanhazip.com 2>/dev/null
}

function get_publicip_fallback {
	# Return the IP address that this machine knows itself as.
	# It certainly may not be the IP address that this machine
	# operates as on the public Internet. The machine might
	# have multiple addresses if it has multiple network adapters.
	set -- $(hostname --ip-address       2>/dev/null) \
	       $(hostname --all-ip-addresses 2>/dev/null)
	while (( $# )) && { ! is_ipv4 "$1" || is_loopback_ip "$1"; }; do
		shift
	done
	printf '%s\n' "$1" # return this value
}

function get_publicipv6_fallback {
	set -- $(hostname --ip-address       2>/dev/null) \
	       $(hostname --all-ip-addresses 2>/dev/null)
	while (( $# )) && { ! is_ipv6 "$1" || is_loopback_ipv6 "$1"; }; do
		shift
	done
	printf '%s\n' "$1" # return this value
}

function is_ipv4 {
	# helper for get_publicip_fallback
	[[ "$1" == *.*.*.* ]]
}

function is_ipv6 {
	[[ "$1" == *:*:* ]]
}

function is_loopback_ip {
	# helper for get_publicip_fallback
	[[ "$1" == 127.* ]]
}

function is_loopback_ipv6 {
	[[ "$1" == ::1 ]]
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
