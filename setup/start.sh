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


# Gather information from the user about the hostname and public IP
# address of this host.
if [ -z "$PUBLIC_HOSTNAME" ]; then
	echo
	echo "Enter the hostname you want to assign to this machine."
	echo "We've guessed a value. Just backspace it if it's wrong."
	echo "Josh uses box.occams.info as his hostname. Yours should"
	echo "be similar."
	echo
	read -e -i "`hostname`" -p "Hostname: " PUBLIC_HOSTNAME
fi

if [ -z "$PUBLIC_IP" ]; then
	echo
	echo "Enter the public IP address of this machine, as given to"
	echo "you by your ISP. We've guessed a value, but just backspace"
	echo "it if it's wrong."
	echo
	read -e -i "`hostname -i`" -p "Public IP: " PUBLIC_IP
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
EOF

# For docker, we don't want any of our scripts to start daemons.
# Mask the 'service' program by defining a function of the same name
# so that whenever we try to restart a service we just silently do
# nothing.
if [ "$NO_RESTART_SERVICES" == "1" ]; then
	function service {
		# we could output some status, but it's not important
		echo skipping service $@ > /dev/null;
	}
fi

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
sleep 2 # wait for the daemon to start
curl -d POSTDATA http://127.0.0.1:10222/dns/update

if [ -t 0 ]; then # are we in an interactive shell?
if [ -z "`tools/mail.py user`" ]; then
	# The outut of "tools/mail.py user" is a list of mail users. If there
	# are none configured, ask the user to configure one.
	echo
	echo "Let's create your first mail user."
	read -e -i "user@$PUBLIC_HOSTNAME" -p "Email Address: " EMAIL_ADDR
	tools/mail.py user add $EMAIL_ADDR # will ask for password
	tools/mail.py alias add hostmaster@$PUBLIC_HOSTNAME $EMAIL_ADDR
	tools/mail.py alias add postmaster@$PUBLIC_HOSTNAME $EMAIL_ADDR
fi
fi

