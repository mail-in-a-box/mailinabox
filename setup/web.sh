#!/bin/bash
# HTTP: Turn on a web server serving static files
#################################################

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

apt_install nginx php5-fpm

rm -f /etc/nginx/sites-enabled/default

# copy in a nginx configuration file for common and best-practices
# SSL settings from @konklone
cp conf/nginx-ssl.conf /etc/nginx/nginx-ssl.conf

# Fix some nginx defaults.
# The server_names_hash_bucket_size seems to prevent long domain names?
tools/editconf.py /etc/nginx/nginx.conf -s \
	server_names_hash_bucket_size="64;"

# Bump up max_children to support more concurrent connections
tools/editconf.py /etc/php5/fpm/pool.d/www.conf -c ';' \
	pm.max_children=8

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

# We previously installed a custom init script to start the PHP FastCGI daemon.
# Remove it now that we're using php5-fpm.
if [ -L /etc/init.d/php-fastcgi ]; then
	echo "Removing /etc/init.d/php-fastcgi, php5-cgi..."
	rm -f /etc/init.d/php-fastcgi
	hide_output update-rc.d php-fastcgi remove
	apt-get -y purge php5-cgi
fi

# Put our webfinger script into a well-known location.
for f in webfinger; do
	cp tools/$f.php /usr/local/bin/mailinabox-$f.php
	chown www-data.www-data /usr/local/bin/mailinabox-$f.php
done

# Remove obsoleted scripts.
# exchange-autodiscover is now handled by Z-Push.
for f in exchange-autodiscover; do
	rm -f /usr/local/bin/mailinabox-$f.php
done

# Make some space for users to customize their webfinger responses.
mkdir -p $STORAGE_ROOT/webfinger/acct;
chown -R $STORAGE_USER $STORAGE_ROOT/webfinger

# Start services.
restart_service nginx
restart_service php5-fpm

# Open ports.
ufw_allow http
ufw_allow https

