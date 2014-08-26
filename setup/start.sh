#!/bin/bash
# This is the entry point for configuring the system.
#####################################################

source setup/functions.sh # load our functions

# Check system setup: Are we running as root on Ubuntu 14.04 on a
# machine with enough memory? If not, this shows an error and exits.
. setup/preflight.sh

# Recall the last settings used if we're running this a second time.
if [ -f /etc/mailinabox.conf ]; then
	# Run any system migrations before proceeding. Since this is a second run,
	# we assume we have Python already installed.
	setup/migrate.py --migrate

	# Load the old .conf file to get existing configuration options loaded
	# into variables with a DEFAULT_ prefix.
	cat /etc/mailinabox.conf | sed s/^/DEFAULT_/ > /tmp/mailinabox.prev.conf
	source /tmp/mailinabox.prev.conf
	rm -f /tmp/mailinabox.prev.conf
fi

# Ask the user for the PRIMARY_HOSTNAME, PUBLIC_IP, PUBLIC_IPV6, and CSR_COUNTRY
# if values have not already been set in environment variables. When running
# non-interactively, be sure to set values for all!
. setup/questions.sh

# Automatic configuration, e.g. as used in our Vagrant configuration.
if [ "$PUBLIC_IP" = "auto" ]; then
	# Use a public API to get our public IP address, or fall back to local network configuration.
	PUBLIC_IP=$(get_publicip_from_web_service 4 || get_default_privateip 4)
fi
if [ "$PUBLIC_IPV6" = "auto" ]; then
	# Use a public API to get our public IPv6 address, or fall back to local network configuration.
	PUBLIC_IPV6=$(get_publicip_from_web_service 6 || get_default_privateip 6)
fi
if [ "$PRIMARY_HOSTNAME" = "auto-easy" ]; then
	# Generate a probably-unique subdomain under our justtesting.email domain.
	PRIMARY_HOSTNAME=`echo $PUBLIC_IP | sha1sum | cut -c1-5`.justtesting.email
fi

# Show the configuration, since the user may have not entered it manually.
echo
echo "Primary Hostname: $PRIMARY_HOSTNAME"
echo "Public IP Address: $PUBLIC_IP"
if [ ! -z "$PUBLIC_IPV6" ]; then
	echo "Public IPv6 Address: $PUBLIC_IPV6"
fi
if [ "$PRIVATE_IP" != "$PUBLIC_IP" ]; then
	echo "Private IP Address: $PRIVATE_IP"
fi
if [ "$PRIVATE_IPV6" != "$PUBLIC_IPV6" ]; then
	echo "Private IPv6 Address: $PRIVATE_IPV6"
fi
echo "Mail-in-a-Box Version: " $(git describe)
echo

# Run some network checks to make sure setup on this machine makes sense.
if [ -z "$SKIP_NETWORK_CHECKS" ]; then
	. setup/network-checks.sh
fi

# Create the user named "user-data" and store all persistent user
# data (mailboxes, etc.) in that user's home directory.
if [ -z "$STORAGE_ROOT" ]; then
	STORAGE_USER=user-data
	if [ ! -d /home/$STORAGE_USER ]; then useradd -m $STORAGE_USER; fi
	STORAGE_ROOT=/home/$STORAGE_USER
	mkdir -p $STORAGE_ROOT
	echo $(setup/migrate.py --current) > $STORAGE_ROOT/mailinabox.version
	chown $STORAGE_USER.$STORAGE_USER $STORAGE_ROOT/mailinabox.version
fi

# Save the global options in /etc/mailinabox.conf so that standalone
# tools know where to look for data.
cat > /etc/mailinabox.conf << EOF;
STORAGE_USER=$STORAGE_USER
STORAGE_ROOT=$STORAGE_ROOT
PRIMARY_HOSTNAME=$PRIMARY_HOSTNAME
PUBLIC_IP=$PUBLIC_IP
PUBLIC_IPV6=$PUBLIC_IPV6
PRIVATE_IP=$PRIVATE_IP
PRIVATE_IPV6=$PRIVATE_IPV6
CSR_COUNTRY=$CSR_COUNTRY
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
. setup/owncloud.sh
. setup/zpush.sh
. setup/management.sh

# Write the DNS and nginx configuration files.
sleep 5 # wait for the daemon to start
curl -s -d POSTDATA --user $(</var/lib/mailinabox/api.key): http://127.0.0.1:10222/dns/update
curl -s -d POSTDATA --user $(</var/lib/mailinabox/api.key): http://127.0.0.1:10222/web/update

# If there aren't any mail users yet, create one.
. setup/firstuser.sh

# Done.
echo
echo "-----------------------------------------------"
echo
echo Your Mail-in-a-Box is running.
echo
echo Please log in to the control panel for further instructions at:
echo
if management/status_checks.py --check-primary-hostname; then
	# Show the nice URL if it appears to be resolving and has a valid certificate.
	echo https://$PRIMARY_HOSTNAME/admin
	echo
	echo If you have a DNS problem use the box\'s IP address and check the SSL fingerprint:
	echo https://$PUBLIC_IP/admin
else
	echo https://$PUBLIC_IP/admin
	echo
	echo You will be alerted that the website has an invalid certificate. Check that
	echo the certificate fingerprint matches:
	echo
fi
openssl x509 -in $STORAGE_ROOT/ssl/ssl_certificate.pem -noout -fingerprint \
        | sed "s/SHA1 Fingerprint=//"
echo
echo Then you can confirm the security exception and continue.
echo

