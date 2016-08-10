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
apt_install nginx php5-fpm

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
tools/editconf.py /etc/php5/fpm/php.ini -c ';' \
	expose_php=Off

# Set PHPs default charset to UTF-8, since we use it. See #367.
tools/editconf.py /etc/php5/fpm/php.ini -c ';' \
        default_charset="UTF-8"

# Bump up PHP's max_children to support more concurrent connections
tools/editconf.py /etc/php5/fpm/pool.d/www.conf -c ';' \
	pm.max_children=8

# Other nginx settings will be configured by the management service
# since it depends on what domains we're serving, which we don't know
# until mail accounts have been created.

# make a default homepage
if [ -d $STORAGE_ROOT/www/static ]; then mv $STORAGE_ROOT/www/static $STORAGE_ROOT/www/default; fi # migration #NODOC
mkdir -p $STORAGE_ROOT/www/default
if [ ! -f $STORAGE_ROOT/www/default/index.html ]; then
	cp conf/www_default.html $STORAGE_ROOT/www/default/index.html
fi
chown -R $STORAGE_USER $STORAGE_ROOT/www

# We previously installed a custom init script to start the PHP FastCGI daemon. #NODOC
# Remove it now that we're using php5-fpm. #NODOC
if [ -L /etc/init.d/php-fastcgi ]; then
	echo "Removing /etc/init.d/php-fastcgi, php5-cgi..." #NODOC
	rm -f /etc/init.d/php-fastcgi #NODOC
	hide_output update-rc.d php-fastcgi remove #NODOC
	apt-get -y purge php5-cgi #NODOC
fi

# Remove obsoleted scripts. #NODOC
# exchange-autodiscover is now handled by Z-Push. #NODOC
for f in webfinger exchange-autodiscover; do #NODOC
	rm -f /usr/local/bin/mailinabox-$f.php #NODOC
done #NODOC

# Start services.
restart_service nginx
restart_service php5-fpm

# Open ports.
ufw_allow http
ufw_allow https

