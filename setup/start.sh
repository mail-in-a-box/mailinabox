#!/bin/bash
# This is the entry point for configuring the system.
#####################################################

source setup/functions.sh # load our functions

if [ -t 0 ]; then
	# In an interactive shell...
	echo
	echo "Hello and thanks for deploying a Mail-in-a-Box!"
	echo "-----------------------------------------------"
	echo
	echo "I'm going to ask you a few questions. To change your answers later,"
	echo "later, just re-run this script."
fi

# Check system setup.

if [ "`lsb_release -d | sed 's/.*:\s*//'`" != "Ubuntu 14.04 LTS" ]; then
	echo
	echo "Mail-in-a-Box only supports being installed on Ubuntu 14.04, sorry. You are running:"
	echo
	lsb_release -d | sed 's/.*:\s*//'
	echo
	echo "We can't write scripts that run on every possible setup, sorry."
	exit
fi

# Recall the last settings used if we're running this a second time.
if [ -f /etc/mailinabox.conf ]; then
	# Run any system migrations before proceeding. Since this is a second run,
	# we assume we have Python already installed.
	setup/migrate.py --migrate

	# Okay now load the old .conf file to get existing configuration options.
	cat /etc/mailinabox.conf | sed s/^/DEFAULT_/ > /tmp/mailinabox.prev.conf
	source /tmp/mailinabox.prev.conf
	MIGRATIONID=$DEFAULT_MIGRATIONID
else
	# What migration are we at for new installs?
	MIGRATIONID=$(setup/migrate.py --current)
fi

# The box needs a name.
if [ -z "$PRIMARY_HOSTNAME" ]; then
	if [ -z "$DEFAULT_PRIMARY_HOSTNAME" ]; then
		# This is the first run. Ask the user for his email address so we can
		# provide the best default for the box's hostname.
		echo
		echo "What email address are you setting this box up to manage?"
		echo ""
		echo "The part after the @-sign must be a domain name or subdomain"
		echo "that you control. You can add other email addresses to this"
		echo "box later (including email addresses on other domain names"
		echo "or subdomains you control)."
		echo
		echo "We've guessed an email address. Backspace it and type in what"
		echo "you really want."
		echo
		read -e -i "me@`get_default_hostname`" -p "Email Address: " EMAIL_ADDR

		while ! management/mailconfig.py validate-email "$EMAIL_ADDR"
		do
		   echo "That's not a valid email address."
		   echo
		read -e -i "$EMAIL_ADDR" -p "Email Address: " EMAIL_ADDR
		done

		# Take the part after the @-sign as the user's domain name, and add
		# 'box.' to the beginning to create a default hostname for this machine.
		DEFAULT_PRIMARY_HOSTNAME=box.$(echo $EMAIL_ADDR | sed 's/.*@//')
	fi

	echo
	echo "This box needs a name, called a 'hostname'. The name will form a part"
	echo "of the box's web address."
	echo
	echo "We recommend that the name be a subdomain of the domain in your email"
	echo "address, so we're suggesting $DEFAULT_PRIMARY_HOSTNAME."
	echo
	echo "You can change it, but we recommend you don't."
	echo

	read -e -i "$DEFAULT_PRIMARY_HOSTNAME" -p "Hostname: " PRIMARY_HOSTNAME
fi

# If the machine is behind a NAT, inside a VM, etc., it may not know
# its IP address on the public network / the Internet. We need to
# confirm our best guess with the user.
if [ -z "$PUBLIC_IP" ]; then
	if [ -z "$DEFAULT_PUBLIC_IP" ]; then
		# set a default on first run
		DEFAULT_PUBLIC_IP=`get_default_publicip`
	fi

	echo
	echo "Enter the public IP address of this machine, as given to you by your"
	echo "ISP. We've guessed a value, but just backspace it if it's wrong."
	echo

	read -e -i "$DEFAULT_PUBLIC_IP" -p "Public IP: " PUBLIC_IP
fi

# Same for IPv6.
if [ -z "$PUBLIC_IPV6" ]; then
	if [ -z "$DEFAULT_PUBLIC_IPV6" ]; then
		# set a default on first run
		DEFAULT_PUBLIC_IPV6=`get_default_publicipv6`
	fi

	echo
	echo "(Optional) Enter the IPv6 address of this machine. Leave blank"
	echo "           if the machine does not have an IPv6 address."

	read -e -i "$DEFAULT_PUBLIC_IPV6" -p "Public IPv6: " PUBLIC_IPV6
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
	echo
	echo "Enter the two-letter, uppercase country code for where you"
	echo "live or where your organization is based. (This is used to"
	echo "create an SSL certificate.)"
	echo

	#if [ -z "$DEFAULT_CSR_COUNTRY" ]; then
	#	# set a default on first run
	#	DEFAULT_CSR_COUNTRY=...?
	#fi

	read -e -i "$DEFAULT_CSR_COUNTRY" -p "Country Code: " CSR_COUNTRY
fi

# Automatic configuration, e.g. as used in our Vagrant configuration.
if [ "$PUBLIC_IP" = "auto" ]; then
	# Use a public API to get our public IP address.
	PUBLIC_IP=`get_default_publicip`
	echo "IP Address: $PUBLIC_IP"
fi
if [ "$PUBLIC_IPV6" = "auto" ]; then
	# Use a public API to get our public IP address.
	PUBLIC_IPV6=`get_default_publicipv6`
	echo "IPv6 Address: $PUBLIC_IPV6"
fi
if [ "$PRIMARY_HOSTNAME" = "auto-easy" ]; then
	# Generate a probably-unique subdomain under our justtesting.email domain.
	PRIMARY_HOSTNAME=m`get_default_publicip | sha1sum | cut -c1-5`.justtesting.email
	echo "Public Hostname: $PRIMARY_HOSTNAME"
fi


# Create the user named "user-data" and store all persistent user
# data (mailboxes, etc.) in that user's home directory.
if [ -z "$STORAGE_ROOT" ]; then
	STORAGE_USER=user-data
	if [ ! -d /home/$STORAGE_USER ]; then useradd -m $STORAGE_USER; fi
	STORAGE_ROOT=/home/$STORAGE_USER
	mkdir -p $STORAGE_ROOT
fi

# Save the global options in /etc/mailinabox.conf so that standalone
# tools know where to look for data.
cat > /etc/mailinabox.conf << EOF;
STORAGE_USER=$STORAGE_USER
STORAGE_ROOT=$STORAGE_ROOT
PRIMARY_HOSTNAME=$PRIMARY_HOSTNAME
PUBLIC_IP=$PUBLIC_IP
PUBLIC_IPV6=$PUBLIC_IPV6
CSR_COUNTRY=$CSR_COUNTRY
MIGRATIONID=$MIGRATIONID
EOF

# Start service configuration.
. setup/system.sh
. setup/ssl.sh
. setup/dns.sh
. setup/mail-postfix.sh
. setup/mail-dovecot.sh
. setup/mail-users.sh
. setup/dkim.sh
. setup/spamassassin.sh
. setup/web.sh
. setup/webmail.sh
. setup/management.sh

# Write the DNS and nginx configuration files.
sleep 5 # wait for the daemon to start
curl -s -d POSTDATA --user $(</var/lib/mailinabox/api.key): http://127.0.0.1:10222/dns/update
curl -s -d POSTDATA --user $(</var/lib/mailinabox/api.key): http://127.0.0.1:10222/web/update

# If there aren't any mail users yet, create one.
if [ -z "`tools/mail.py user`" ]; then
	# The outut of "tools/mail.py user" is a list of mail users. If there
	# aren't any yet, it'll be empty.

	# If we didn't ask for an email address at the start, do so now.
	if [ -z "$EMAIL_ADDR" ]; then
		# In an interactive shell, ask the user for an email address.
		if [ -t 0 ]; then
			echo
			echo "Let's create your first mail user."
			read -e -i "user@$PRIMARY_HOSTNAME" -p "Email Address: " EMAIL_ADDR

		# But in a non-interactive shell, just make something up. This
		# is normally for testing.
		else
			# Use me@PRIMARY_HOSTNAME
			EMAIL_ADDR=me@$PRIMARY_HOSTNAME
			EMAIL_PW=1234
			echo
			echo "Creating a new mail account for $EMAIL_ADDR with password $EMAIL_PW."
			echo
		fi
	else
		echo
		echo "Okay. I'm about to set up $EMAIL_ADDR for you."
	fi

	# Create the user's mail account. This will ask for a password if none was given above.
	tools/mail.py user add $EMAIL_ADDR $EMAIL_PW

	# Create an alias to which we'll direct all automatically-created administrative aliases.
	tools/mail.py alias add administrator@$PRIMARY_HOSTNAME $EMAIL_ADDR
fi

