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
	set -- $(hostname --fqdn      2>/dev/null ||
                 hostname --all-fqdns 2>/dev/null ||
                 hostname             2>/dev/null)
	printf '%s\n' "$1"
}

function get_default_publicip {
	get_publicip_from_web_service || get_publicip_from_dns
}

function get_publicip_from_web_service {
	curl --fail --silent icanhazip.com 2>/dev/null
}

function get_publicip_from_dns {
	set -- $(hostname --ip-address       2>/dev/null) \
	       $(hostname --all-ip-addresses 2>/dev/null)
	while (( $# )) && is_loopback_ip "$1"; do
		shift
	done
	printf '%s\n' "$1"
}

function is_loopback_ip {
	[[ "$1" == 127.* ]]
}

function ufw_allow {
	if [ -z "$DISABLE_FIREWALL" ]; then
		# ufw has completely unhelpful output
		ufw allow $1 > /dev/null;
	fi
}

