if [ -z "$NONINTERACTIVE" ]; then
	# Install 'dialog' so we can ask the user questions. The original motivation for
	# this was being able to ask the user for input even if stdin has been redirected,
	# e.g. if we piped a bootstrapping install script to bash to get started. In that
	# case, the nifty '[ -t 0 ]' test won't work. But with Vagrant we must suppress so we
	# use a shell flag instead. Really supress any output from installing dialog.
	#
	# Also install depencies needed to validate the email address.
	echo Installing packages needed for setup...
	apt_get_quiet install dialog python3 python3-pip  || exit 1

	# email_validator is repeated in setup/management.sh
	hide_output pip3 install "email_validator==0.1.0-rc4" || exit 1

	message_box "Mail-in-a-Box Installation" \
		"Hello and thanks for deploying a Mail-in-a-Box!
		\n\nI'm going to ask you a few questions.
		\n\nTo change your answers later, just run 'sudo mailinabox' from the command line."
fi

# The box needs a name.
if [ -z "$PRIMARY_HOSTNAME" ]; then
	if [ -z "$DEFAULT_PRIMARY_HOSTNAME" ]; then
		# We recommend to use box.example.com as this hosts name. The
		# domain the user possibly wants to use is example.com then.
		# We strip the string "box." from the hostname to get the mail
		# domain. If the hostname differs, nothing happens here.
		DEFAULT_DOMAIN_GUESS=$(echo $(get_default_hostname) | sed -e 's/^box\.//')

		# This is the first run. Ask the user for his email address so we can
		# provide the best default for the box's hostname.
		input_box "Your Email Address" \
"What email address are you setting this box up to manage?
\n\nThe part after the @-sign must be a domain name or subdomain
that you control. You can add other email addresses to this
box later (including email addresses on other domain names
or subdomains you control).
\n\nWe've guessed an email address. Backspace it and type in what
you really want.
\n\nEmail Address:" \
			"me@$DEFAULT_DOMAIN_GUESS" \
			EMAIL_ADDR

		if [ -z "$EMAIL_ADDR" ]; then
			# user hit ESC/cancel
			exit
		fi
		while ! management/mailconfig.py validate-email "$EMAIL_ADDR"
		do
			input_box "Your Email Address" \
				"That's not a valid email address.\n\nWhat email address are you setting this box up to manage?" \
				$EMAIL_ADDR \
				EMAIL_ADDR
			if [ -z "$EMAIL_ADDR" ]; then
				# user hit ESC/cancel
				exit
			fi
		done

		# Take the part after the @-sign as the user's domain name, and add
		# 'box.' to the beginning to create a default hostname for this machine.
		DEFAULT_PRIMARY_HOSTNAME=box.$(echo $EMAIL_ADDR | sed 's/.*@//')
	fi

	input_box "Hostname" \
"This box needs a name, called a 'hostname'. The name will form a part of the box's web address.
\n\nWe recommend that the name be a subdomain of the domain in your email
address, so we're suggesting $DEFAULT_PRIMARY_HOSTNAME.
\n\nYou can change it, but we recommend you don't.
\n\nHostname:" \
		$DEFAULT_PRIMARY_HOSTNAME \
		PRIMARY_HOSTNAME

	if [ -z "$PRIMARY_HOSTNAME" ]; then
		# user hit ESC/cancel
		exit
	fi
fi

# If the machine is behind a NAT, inside a VM, etc., it may not know
# its IP address on the public network / the Internet. Ask the Internet
# and possibly confirm with user.
if [ -z "$PUBLIC_IP" ]; then
	# Ask the Internet.
	GUESSED_IP=$(get_publicip_from_web_service 4)

	# On the first run, if we got an answer from the Internet then don't
	# ask the user.
	if [[ -z "$DEFAULT_PUBLIC_IP" && ! -z "$GUESSED_IP" ]]; then
		PUBLIC_IP=$GUESSED_IP

	# Otherwise on the first run at least provide a default.
	elif [[ -z "$DEFAULT_PUBLIC_IP" ]]; then
		DEFAULT_PUBLIC_IP=$(get_default_privateip 4)

	# On later runs, if the previous value matches the guessed value then
	# don't ask the user either.
	elif [ "$DEFAULT_PUBLIC_IP" == "$GUESSED_IP" ]; then
		PUBLIC_IP=$GUESSED_IP
	fi

	if [ -z "$PUBLIC_IP" ]; then
		input_box "Public IP Address" \
			"Enter the public IP address of this machine, as given to you by your ISP.
			\n\nPublic IP address:" \
			$DEFAULT_PUBLIC_IP \
			PUBLIC_IP

		if [ -z "$PUBLIC_IP" ]; then
			# user hit ESC/cancel
			exit
		fi
	fi
fi

# Same for IPv6. But it's optional. Also, if it looks like the system
# doesn't have an IPv6, don't ask for one.
if [ -z "$PUBLIC_IPV6" ]; then
	# Ask the Internet.
	GUESSED_IP=$(get_publicip_from_web_service 6)
	MATCHED=0
	if [[ -z "$DEFAULT_PUBLIC_IPV6" && ! -z "$GUESSED_IP" ]]; then
		PUBLIC_IPV6=$GUESSED_IP
	elif [[ "$DEFAULT_PUBLIC_IPV6" == "$GUESSED_IP" ]]; then
		# No IPv6 entered and machine seems to have none, or what
		# the user entered matches what the Internet tells us.
		PUBLIC_IPV6=$GUESSED_IP
		MATCHED=1
	elif [[ -z "$DEFAULT_PUBLIC_IPV6" ]]; then
		DEFAULT_PUBLIC_IP=$(get_default_privateip 6)
	fi

	if [[ -z "$PUBLIC_IPV6" && $MATCHED == 0 ]]; then
		input_box "IPv6 Address (Optional)" \
			"Enter the public IPv6 address of this machine, as given to you by your ISP.
			\n\nLeave blank if the machine does not have an IPv6 address.
			\n\nPublic IPv6 address:" \
			$DEFAULT_PUBLIC_IPV6 \
			PUBLIC_IPV6

		if [ ! $PUBLIC_IPV6_EXITCODE ]; then
			# user hit ESC/cancel
			exit
		fi
	fi
fi

# Get the IP addresses of the local network interface(s) that are connected
# to the Internet. We need these when we want to have services bind only to
# the public network interfaces (not loopback, not tunnel interfaces).
if [ -z "$PRIVATE_IP" ]; then
	PRIVATE_IP=$(get_default_privateip 4)
fi
if [ -z "$PRIVATE_IPV6" ]; then
	PRIVATE_IPV6=$(get_default_privateip 6)
fi
if [[ -z "$PRIVATE_IP" && -z "$PRIVATE_IPV6" ]]; then
	echo
	echo "I could not determine the IP or IPv6 address of the network inteface"
	echo "for connecting to the Internet. Setup must stop."
	echo
	hostname -I
	route
	echo
	exit
fi

# We need a country code to generate a certificate signing request. However
# if a CSR already exists then we won't be generating a new one and there's
# no reason to ask for the country code now. $STORAGE_ROOT has not yet been
# set so we'll check if $DEFAULT_STORAGE_ROOT and $DEFAULT_CSR_COUNTRY are
# set (the values from the current mailinabox.conf) and if the CSR exists
# in the expected location.
if [ ! -z "$DEFAULT_STORAGE_ROOT" ] && [ ! -z "$DEFAULT_CSR_COUNTRY" ] && [ -f $DEFAULT_STORAGE_ROOT/ssl/ssl_cert_sign_req.csr ]; then
	CSR_COUNTRY=$DEFAULT_CSR_COUNTRY
fi

if [ -z "$CSR_COUNTRY" ]; then
	# Get a list of country codes. Separate codes from country names with a ^.
	# The input_menu function modifies shell word expansion to ignore spaces
	# (since country names can have spaces) and use ^ instead.
	country_code_list=$(grep -v "^#" setup/csr_country_codes.tsv | sed "s/\(..\)\t\([^\t]*\).*/\1^\2/")

	input_menu "Country Code" \
		"Choose the country where you live or where your organization is based.
		\n\n(This is used to create an SSL certificate.)
		\n\nCountry Code:" \
		"$country_code_list" \
		CSR_COUNTRY

	if [ -z "$CSR_COUNTRY" ]; then
		# user hit ESC/cancel
		exit
	fi
fi
