#!/bin/bash
# This is the entry point for configuring the system.
#####################################################

# Check system setup.

if [ "`lsb_release -d | sed 's/.*:\s*//'`" != "Ubuntu 14.04 LTS" ]; then
	echo "Mail-in-a-Box only supports being installed on Ubuntu 14.04, sorry. You are running:"
	echo
	lsb_release -d | sed 's/.*:\s*//'
	echo
	echo "We can't write scripts that run on every possible setup, sorry."
	exit
fi

# Recall the last settings used if we're running this a second time.
if [ -f /etc/mailinabox.conf ]; then
	cat /etc/mailinabox.conf | sed s/^/DEFAULT_/ > /tmp/mailinabox.prev.conf
	source /tmp/mailinabox.prev.conf
fi

# Gather information from the user about the hostname and public IP
# address of this host.
if [ -z "$PUBLIC_HOSTNAME" ]; then
	echo
	echo "Enter the hostname you want to assign to this machine."
	echo "We've guessed a value. Just backspace it if it's wrong."
	echo "Josh uses box.occams.info as his hostname. Yours should"
	echo "be similar."
	echo

	if [ -z "$DEFAULT_PUBLIC_HOSTNAME" ]; then
		# set a default on first run
		DEFAULT_PUBLIC_HOSTNAME=`hostname`
	fi

	read -e -i "$DEFAULT_PUBLIC_HOSTNAME" -p "Hostname: " PUBLIC_HOSTNAME
fi

if [ -z "$PUBLIC_IP" ]; then
	echo
	echo "Enter the public IP address of this machine, as given to"
	echo "you by your ISP. We've guessed a value, but just backspace"
	echo "it if it's wrong."
	echo

	if [ -z "$DEFAULT_PUBLIC_IP" ]; then
		# set a default on first run
		DEFAULT_PUBLIC_IP=`hostname -i`
	fi

	read -e -i "$DEFAULT_PUBLIC_IP" -p "Public IP: " PUBLIC_IP
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
if [ "$PUBLIC_IP" == "auto" ]; then
	# Assume `hostname -i` gives the correct public IP address for the machine.
	PUBLIC_IP=`hostname -i`
	echo "IP Address: $PUBLIC_IP"
fi
if [ "$PUBLIC_IP" == "auto-web" ]; then
	# Use a public API to get our public IP address.
	PUBLIC_IP=`curl -s icanhazip.com`
	echo "IP Address: $PUBLIC_IP"
fi
if [ "$PUBLIC_HOSTNAME" == "auto-easy" ]; then
	# Generate a probably-unique subdomain under our justtesting.email domain.
	PUBLIC_HOSTNAME=m`hostname -i | sha1sum | cut -c1-5`.justtesting.email
	echo "Public Hostname: $PUBLIC_HOSTNAME"
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
STORAGE_ROOT=$STORAGE_ROOT
PUBLIC_HOSTNAME=$PUBLIC_HOSTNAME
PUBLIC_IP=$PUBLIC_IP
CSR_COUNTRY=$CSR_COUNTRY
EOF

# Start service configuration.
. setup/system.sh
. setup/dns.sh
. setup/mail.sh
. setup/dkim.sh
. setup/spamassassin.sh
. setup/web.sh
. setup/webmail.sh
. setup/management.sh

# Write the DNS configuration files.
sleep 5 # wait for the daemon to start
curl -s -d POSTDATA http://127.0.0.1:10222/dns/update

# If there aren't any mail users yet, create one.
if [ -z "`tools/mail.py user`" ]; then
	# The outut of "tools/mail.py user" is a list of mail users. If there
	# aren't any yet, it'll be empty.

	# In an interactive shell, ask the user for an email address.
	if [ -t 0 ]; then
		echo
		echo "Let's create your first mail user."
		read -e -i "user@$PUBLIC_HOSTNAME" -p "Email Address: " EMAIL_ADDR
	else
		# Use me@PUBLIC_HOSTNAME
		EMAIL_ADDR=me@$PUBLIC_HOSTNAME
		EMAIL_PW=1234
		echo
		echo "Creating a new mail account for $EMAIL_ADDR with password $EMAIL_PW."
		echo
	fi

	tools/mail.py user add $EMAIL_ADDR $EMAIL_PW # will ask for password if none given
	tools/mail.py alias add hostmaster@$PUBLIC_HOSTNAME $EMAIL_ADDR
	tools/mail.py alias add postmaster@$PUBLIC_HOSTNAME $EMAIL_ADDR
fi

