function apt_install {
	# Report any packages already installed.
	PACKAGES=$@
	TO_INSTALL=""
	for pkg in $PACKAGES; do
		if dpkg -s $pkg 2>/dev/null | grep "^Status: install ok installed" > /dev/null; then
			echo $pkg is already installed \(`dpkg -s $pkg | grep ^Version: | sed -e "s/.*: //"`\)
		else
			TO_INSTALL="$TO_INSTALL""$pkg "
		fi
	done

	# List the packages about to be installed.
	if [[ ! -z "$TO_INSTALL" ]]; then
		echo installing $TO_INSTALL...
	fi

	# 'DEBIAN_FRONTEND=noninteractive' is to prevent dbconfig-common from asking you questions.
	DEBIAN_FRONTEND=noninteractive apt-get -qq -y install $PACKAGES > /dev/null;
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

function get_publicip_from_web_service {
	# This seems to be the most reliable way to determine the
	# machine's public IP address: asking a very nice web API
	# for how they see us. Thanks go out to icanhazip.com.
	curl --fail --silent icanhazip.com 2>/dev/null
}

function get_publicip_fallback {
	# Return the IP address that this machine knows itself as.
	# It certainly may not be the IP address that this machine
	# operates as on the public Internet. The machine might
	# have multiple addresses if it has multiple network adapters.
	set -- $(hostname --ip-address       2>/dev/null) \
	       $(hostname --all-ip-addresses 2>/dev/null)
	while (( $# )) && is_loopback_ip "$1"; do
		shift
	done
	printf '%s\n' "$1" # return this value
}

function is_loopback_ip {
	# helper for get_publicip_fallback
	[[ "$1" == 127.* ]]
}

function ufw_allow {
	if [ -z "$DISABLE_FIREWALL" ]; then
		# ufw has completely unhelpful output
		ufw allow $1 > /dev/null;
	fi
}

