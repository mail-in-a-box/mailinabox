#!/bin/bash
# HTTP: Turn on a web server serving static files
#################################################

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

apt_install nginx php5-cgi

rm -f /etc/nginx/sites-enabled/default

# copy in a nginx configuration file for common and best-practices
# SSL settings from @konklone
cp conf/nginx-ssl.conf /etc/nginx/nginx-ssl.conf

# Other nginx settings will be configured by the management service
# since it depends on what domains we're serving, which we don't know
# until mail accounts have been created.

# make a default homepage
if [ -d $STORAGE_ROOT/www/static ]; then mv $STORAGE_ROOT/www/static $STORAGE_ROOT/www/default; fi # migration
mkdir -p $STORAGE_ROOT/www/default
if [ ! -f $STORAGE_ROOT/www/default/index.html ]; then
	cp conf/www_default.html $STORAGE_ROOT/www/default/index.html
fi
chown -R $STORAGE_USER $STORAGE_ROOT/www

# Create an init script to start the PHP FastCGI daemon and keep it
# running after a reboot. Allows us to serve Roundcube for webmail.
rm -f /etc/init.d/php-fastcgi
ln -s $(pwd)/conf/phpfcgi-initscript /etc/init.d/php-fastcgi
update-rc.d php-fastcgi defaults

# Put our webfinger server script into a well-known location.
cp tools/webfinger.php /usr/local/bin/mailinabox-webfinger.php
chown www-data.www-data /usr/local/bin/mailinabox-webfinger.php
mkdir -p $STORAGE_ROOT/webfinger/acct;
chown -R $STORAGE_USER $STORAGE_ROOT/webfinger

# Start services.
service nginx restart
service php-fastcgi restart

# Open ports.
ufw_allow http
ufw_allow https

