#!/bin/bash
# HTTP: Turn on a web server serving static files
#################################################

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

# Some Ubuntu images start off with Apache. Remove it since we
# will use nginx. Use autoremove to remove any Apache depenencies.
if [ -f /usr/sbin/apache2 ]; then
	echo Removing apache...
	hide_output apt-get -y purge apache2 apache2-*
	hide_output apt-get -y --purge autoremove
fi

# Install nginx and a PHP FastCGI daemon.
#
# Turn off nginx's default website.

echo "Installing Nginx (web server)..."

apt_install nginx php-cli php-fpm

rm -f /etc/nginx/sites-enabled/default

# Copy in a nginx configuration file for common and best-practices
# SSL settings from @konklone. Replace STORAGE_ROOT so it can find
# the DH params.
rm -f /etc/nginx/nginx-ssl.conf # we used to put it here
sed "s#STORAGE_ROOT#$STORAGE_ROOT#" \
	conf/nginx-ssl.conf > /etc/nginx/conf.d/ssl.conf

# Fix some nginx defaults.
# The server_names_hash_bucket_size seems to prevent long domain names!
# The default, according to nginx's docs, depends on "the size of the
# processor’s cache line." It could be as low as 32. We fixed it at
# 64 in 2014 to accommodate a long domain name (20 characters?). But
# even at 64, a 58-character domain name won't work (#93), so now
# we're going up to 128.
tools/editconf.py /etc/nginx/nginx.conf -s \
	server_names_hash_bucket_size="128;"

# Tell PHP not to expose its version number in the X-Powered-By header.
tools/editconf.py /etc/php/7.2/fpm/php.ini -c ';' \
	expose_php=Off

# Set PHPs default charset to UTF-8, since we use it. See #367.
tools/editconf.py /etc/php/7.2/fpm/php.ini -c ';' \
        default_charset="UTF-8"

# Switch from the dynamic process manager to the ondemand manager see #1216
tools/editconf.py /etc/php/7.2/fpm/pool.d/www.conf -c ';' \
	pm=ondemand

# Bump up PHP's max_children to support more concurrent connections
tools/editconf.py /etc/php/7.2/fpm/pool.d/www.conf -c ';' \
	pm.max_children=8

# Other nginx settings will be configured by the management service
# since it depends on what domains we're serving, which we don't know
# until mail accounts have been created.

# Create the iOS/OS X Mobile Configuration file which is exposed via the
# nginx configuration at /mailinabox-mobileconfig.
mkdir -p /var/lib/mailinabox
chmod a+rx /var/lib/mailinabox
cat conf/ios-profile.xml \
	| sed "s/PRIMARY_HOSTNAME/$PRIMARY_HOSTNAME/" \
	| sed "s/UUID1/$(cat /proc/sys/kernel/random/uuid)/" \
	| sed "s/UUID2/$(cat /proc/sys/kernel/random/uuid)/" \
	| sed "s/UUID3/$(cat /proc/sys/kernel/random/uuid)/" \
	| sed "s/UUID4/$(cat /proc/sys/kernel/random/uuid)/" \
	 > /var/lib/mailinabox/mobileconfig.xml
chmod a+r /var/lib/mailinabox/mobileconfig.xml

# Create the Mozilla Auto-configuration file which is exposed via the
# nginx configuration at /.well-known/autoconfig/mail/config-v1.1.xml.
# The format of the file is documented at:
# https://wiki.mozilla.org/Thunderbird:Autoconfiguration:ConfigFileFormat
# and https://developer.mozilla.org/en-US/docs/Mozilla/Thunderbird/Autoconfiguration/FileFormat/HowTo.
cat conf/mozilla-autoconfig.xml \
	| sed "s/PRIMARY_HOSTNAME/$PRIMARY_HOSTNAME/" \
	 > /var/lib/mailinabox/mozilla-autoconfig.xml
chmod a+r /var/lib/mailinabox/mozilla-autoconfig.xml

# create the MTA-STS policy
cat << EOF | tee /var/lib/mailinabox/mta-sts.txt
version: STSv1
mode: enforce
mx: \$PRIMARY_HOSTNAME
max_age: 86400
EOF
chmod a+r /var/lib/mailinabox/mta-sts.txt

# install the postfix MTA-STS resolver
/usr/bin/pip3 install postfix-mta-sts-resolver
# add a user to use solely for MTA-STS resolution
useradd -c "Daemon for MTA-STS policy checks" mta-sts -s /sbin/nologin
# create systemd services for MTA-STS
cat > /etc/systemd/system/postfix-mta-sts-daemon@.service << EOF
[Unit]
Description=Postfix MTA STS daemon instance
After=syslog.target network.target

[Service]
Type=notify
User=mta-sts
Group=mta-sts
ExecStart=/usr/local/bin/mta-sts-daemon
Restart=always
KillMode=process
TimeoutStartSec=10
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/postfix-mta-sts.service << EOF
[Unit]
Description=Postfix MTA STS daemon
After=syslog.target network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/systemctl start postfix-mta-sts-daemon@main.service
ExecReload=/bin/systemctl start postfix-mta-sts-daemon@backup.service ; /bin/systemctl restart postfix-mta-sts-daemon@main.service ; /bin/systemctl stop postfix-mta-sts-daemon@backup.service
ExecStop=/bin/systemctl stop postfix-mta-sts-daemon@main.service

[Install]
WantedBy=multi-user.target
EOF

# configure the MTA-STS daemon for postfix
cat > /etc/postfix/mta-sts-daemon.yml << EOF
host: 127.0.0.1
port: 8461
cache:
  type: internal
  options:
    cache_size: 10000
default_zone:
  strict_testing: true
  timeout: 4
zones:
  myzone:
    strict_testing: false
    timeout: 4
EOF

# add postfix configuration
tools/editconf.py /etc/postfix/main.cf -s \
	smtp_tls_policy_maps=socketmap:inet:127.0.0.1:8461:postfix

# enable and start the MTA-STS service
/bin/systemctl enable postfix-mta-sts.service
/bin/systemctl start postfix-mta-sts.service

# make a default homepage
if [ -d $STORAGE_ROOT/www/static ]; then mv $STORAGE_ROOT/www/static $STORAGE_ROOT/www/default; fi # migration #NODOC
mkdir -p $STORAGE_ROOT/www/default
if [ ! -f $STORAGE_ROOT/www/default/index.html ]; then
	cp conf/www_default.html $STORAGE_ROOT/www/default/index.html
fi
chown -R $STORAGE_USER $STORAGE_ROOT/www

# Start services.
restart_service nginx
restart_service php7.2-fpm

# Open ports.
ufw_allow http
ufw_allow https

