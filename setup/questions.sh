if [ -z "${NONINTERACTIVE:-}" ]; then
	# Install 'dialog' so we can ask the user questions. The original motivation for
	# this was being able to ask the user for input even if stdin has been redirected,
	# e.g. if we piped a bootstrapping install script to bash to get started. In that
	# case, the nifty '[ -t 0 ]' test won't work. But with Vagrant we must suppress so we
	# use a shell flag instead. Really suppress any output from installing dialog.
	#
	# Also install dependencies needed to validate the email address.
	if [ ! -f /usr/bin/dialog ] || [ ! -f /usr/bin/python3 ] || [ ! -f /usr/bin/pip3 ]; then
		echo Installing packages needed for setup...
		apt-get -q -q update
		apt_get_quiet install dialog python3 python3-pip  || exit 1
	fi

	# Installing email_validator is repeated in setup/management.sh, but in setup/management.sh
	# we install it inside a virtualenv. In this script, we don't have the virtualenv yet
	# so we install the python package globally.
	hide_output pip3 install "email_validator>=1.0.0" || exit 1

	message_box "Mail-in-a-Box Installation" \
		"Hello and thanks for deploying a Mail-in-a-Box!
		\n\nI'm going to ask you a few questions.
		\n\nTo change your answers later, just run 'sudo mailinabox' from the command line.
		\n\nNOTE: You should only install this on a brand new Ubuntu installation 100% dedicated to Mail-in-a-Box. Mail-in-a-Box will, for example, remove apache2."
fi

# The box needs a name.
if [ -z "${PRIMARY_HOSTNAME:-}" ]; then
	if [ -z "${DEFAULT_PRIMARY_HOSTNAME:-}" ]; then
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
		while ! python3 management/mailconfig.py validate-email "$EMAIL_ADDR"
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

	RE='^.+\.localdomain$'
	RE1='^.{4,253}$'
	RE2='^([[:alnum:]][[:alnum:]\-]{0,61}[[:alnum:]]\.)+[a-zA-Z]{2,63}$'
	if [ -z "$PRIMARY_HOSTNAME" ]; then
		# user hit ESC/cancel
		exit 1
	elif [[ $PRIMARY_HOSTNAME =~ $RE ]]; then
		echo "Warning: Hostname cannot be *.localdomain."
	elif ! [[ $PRIMARY_HOSTNAME =~ $RE1 && $PRIMARY_HOSTNAME =~ $RE2 ]]; then
		echo "Warning: Hostname is not a valid fully qualified domain name (FQDN)."
	fi
fi

# If the machine is behind a NAT, inside a VM, etc., it may not know
# its IP address on the public network / the Internet. Ask the Internet
# and possibly confirm with user.
if [ -z "${PUBLIC_IP:-}" ]; then
	# Ask the Internet.
	GUESSED_IP=$(get_publicip_from_web_service 4)

	# On the first run, if we got an answer from the Internet then don't
	# ask the user.
	if [[ -z "${DEFAULT_PUBLIC_IP:-}" && ! -z "$GUESSED_IP" ]]; then
		PUBLIC_IP=$GUESSED_IP

	# Otherwise on the first run at least provide a default.
	elif [[ -z "${DEFAULT_PUBLIC_IP:-}" ]]; then
		DEFAULT_PUBLIC_IP=$(get_default_privateip 4)

	# On later runs, if the previous value matches the guessed value then
	# don't ask the user either.
	elif [ "${DEFAULT_PUBLIC_IP:-}" == "$GUESSED_IP" ]; then
		PUBLIC_IP=$GUESSED_IP
	fi

	if [ -z "${PUBLIC_IP:-}" ]; then
		input_box "Public IP Address" \
			"Enter the public IP address of this machine, as given to you by your ISP.
			\n\nPublic IP address:" \
			${DEFAULT_PUBLIC_IP:-} \
			PUBLIC_IP

		if [ -z "$PUBLIC_IP" ]; then
			# user hit ESC/cancel
			exit
		fi
	fi
fi

# Same for IPv6. But it's optional. Also, if it looks like the system
# doesn't have an IPv6, don't ask for one.
if [ -z "${PUBLIC_IPV6:-}" ]; then
	# Ask the Internet.
	GUESSED_IP=$(get_publicip_from_web_service 6)
	MATCHED=0
	if [[ -z "${DEFAULT_PUBLIC_IPV6:-}" && ! -z "$GUESSED_IP" ]]; then
		PUBLIC_IPV6=$GUESSED_IP
	elif [[ "${DEFAULT_PUBLIC_IPV6:-}" == "$GUESSED_IP" ]]; then
		# No IPv6 entered and machine seems to have none, or what
		# the user entered matches what the Internet tells us.
		PUBLIC_IPV6=$GUESSED_IP
		MATCHED=1
	elif [[ -z "${DEFAULT_PUBLIC_IPV6:-}" ]]; then
		DEFAULT_PUBLIC_IP=$(get_default_privateip 6)
	fi

	if [[ -z "${PUBLIC_IPV6:-}" && $MATCHED == 0 ]]; then
		input_box "IPv6 Address (Optional)" \
			"Enter the public IPv6 address of this machine, as given to you by your ISP.
			\n\nLeave blank if the machine does not have an IPv6 address.
			\n\nPublic IPv6 address:" \
			${DEFAULT_PUBLIC_IPV6:-} \
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
if [ -z "${PRIVATE_IP:-}" ]; then
	PRIVATE_IP=$(get_default_privateip 4)
fi
if [ -z "${PRIVATE_IPV6:-}" ]; then
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

# Automatic configuration, e.g. as used in our Vagrant configuration.
if [ "$PUBLIC_IP" = "auto" ]; then
	# Use a public API to get our public IP address, or fall back to local network configuration.
	PUBLIC_IP=$(get_publicip_from_web_service 4 || get_default_privateip 4)
fi
if [ "$PUBLIC_IPV6" = "auto" ]; then
	# Use a public API to get our public IPv6 address, or fall back to local network configuration.
	PUBLIC_IPV6=$(get_publicip_from_web_service 6 || get_default_privateip 6)
fi
if [ "$PRIMARY_HOSTNAME" = "auto" ]; then
	PRIMARY_HOSTNAME=$(get_default_hostname)
fi

# Set STORAGE_USER and STORAGE_ROOT to default values (user-data and /home/user-data), unless
# we've already got those values from a previous run.
if [ -z "${STORAGE_USER:-}" ]; then
	STORAGE_USER=$([[ -z "${DEFAULT_STORAGE_USER:-}" ]] && echo "user-data" || echo "$DEFAULT_STORAGE_USER")
fi
if [ -z "${STORAGE_ROOT:-}" ]; then
	STORAGE_ROOT=$([[ -z "${DEFAULT_STORAGE_ROOT:-}" ]] && echo "/home/$STORAGE_USER" || echo "$DEFAULT_STORAGE_ROOT")
fi

# Show the configuration, since the user may have not entered it manually.
echo -e "\nLinux Distribution:\t\t${PRETTY_NAME:-$ID-$VERSION_ID}"
CPU=( $(sed -n 's/^model name[[:space:]]*: *//p' /proc/cpuinfo | uniq) )
if [ -n "$CPU" ]; then
	echo -e "Processor (CPU):\t\t${CPU[*]}"
fi
CPU_CORES=$(nproc --all)
echo -e "CPU Cores:\t\t\t$CPU_CORES"
echo -e "Architecture:\t\t\t$HOSTTYPE ($ARCHITECTURE-bit)"
echo -e "Total memory (RAM):\t\t$(printf "%'d" $((TOTAL_PHYSICAL_MEM / 1024))) MiB ($(printf "%'d" $((((TOTAL_PHYSICAL_MEM * 1024) / 1000) / 1000))) MB)"
echo -e "Total swap space:\t\t$(printf "%'d" $((TOTAL_SWAP / 1024))) MiB ($(printf "%'d" $((((TOTAL_SWAP * 1024) / 1000) / 1000))) MB)"
if command -v lspci >/dev/null; then
	GPU=( $(lspci 2>/dev/null | grep -i 'vga\|3d\|2d' | sed -n 's/^.*: //p') )
fi
if [ -n "$GPU" ]; then
	echo -e "Graphics Processor (GPU):\t${GPU[*]}"
fi
echo -e "Computer name:\t\t\t$HOSTNAME"
echo -e "Primary Hostname:\t\t$PRIMARY_HOSTNAME"
if [ -n "$PUBLIC_IPV6" ]; then
	echo -e "Public IPv4 Address:\t\t$PUBLIC_IP"
	echo -e "Public IPv6 Address:\t\t$PUBLIC_IPV6"
else
	echo -e "Public IP Address:\t\t$PUBLIC_IP"
fi
if [ -n "$PRIVATE_IPV6" ]; then
	if [ "$PRIVATE_IP" != "$PUBLIC_IP" ]; then
		echo -e "Private IPv4 Address:\t\t$PRIVATE_IP"
	fi
	if [ "$PRIVATE_IPV6" != "$PUBLIC_IPV6" ]; then
		echo -e "Private IPv6 Address:\t\t$PRIVATE_IPV6"
	fi
else
	if [ "$PRIVATE_IP" != "$PUBLIC_IP" ]; then
		echo -e "Private IP Address:\t\t$PRIVATE_IP"
	fi
fi
TIME_ZONE=$(timedatectl 2>/dev/null | grep -i 'time zone\|timezone' | sed -n 's/^.*: //p')
echo -e "Time zone:\t\t\t$TIME_ZONE\n"
if command -v systemd-detect-virt >/dev/null && CONTAINER=$(systemd-detect-virt -c); then
	echo -e "Virtualization container:\t$CONTAINER\n"
fi
if command -v systemd-detect-virt >/dev/null && VM=$(systemd-detect-virt -v); then
	echo -e "Virtual Machine (VM) hypervisor:$VM\n"
fi
if command -v git >/dev/null && [ -d .git ]; then
	echo -e "Mail-in-a-Box Version:\t\t$(git describe)\n"
fi
