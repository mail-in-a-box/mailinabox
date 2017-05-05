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

# make a default homepage
if [ -d $STORAGE_ROOT/www/static ]; then mv $STORAGE_ROOT/www/static $STORAGE_ROOT/www/default; fi # migration #NODOC
mkdir -p $STORAGE_ROOT/www/default
if [ ! -f $STORAGE_ROOT/www/default/index.html ]; then
	cp conf/www_default.html $STORAGE_ROOT/www/default/index.html
fi
chown -R $STORAGE_USER $STORAGE_ROOT/www


# download jQuery and Bootstrap local files
if [ ! -d $STORAGE_ROOT/www/default/assets ]; then
	echo "Downloading Assets..."

	js_lib=$STORAGE_ROOT/www/default/assets/js/lib
	css_lib=$STORAGE_ROOT/www/default/assets/css/lib

	#jQuery CDN URL
	jquery_version=2.1.4
	jquery_url=https://code.jquery.com

	#Bootstrap CDN URL
	bootstrap_version=3.3.7
	bootstrap_url=https://maxcdn.bootstrapcdn.com/bootstrap/$bootstrap_version/css

	#get the Javascript files
	if [ ! -d $js_lib ]; then
		mkdir -p $js_lib

		wget_verify $jquery_url/jquery-$jquery_version.min.js 43dc554608df885a59ddeece1598c6ace434d747 $js_lib
		wget_verify https://maxcdn.bootstrapcdn.com/bootstrap/$bootstrap_version/js/bootstrap.min.js 430a443d74830fe9be26efca431f448c1b3740f9 $js_lib
	fi

	# get the CSS(map) files
	if [ ! -d $css_lib ]; then
		mkdir -p $css_lib

		wget_verify $bootstrap_url/bootstrap-theme.min.css 8256575374f430476bdcd49de98c77990229ce31 $css_lib
		wget_verify $bootstrap_url/bootstrap-theme.min.css.map 87f7dfd79d77051ac2eca7d093d961fbd1c8f6eb $css_lib
		wget_verify $bootstrap_url/bootstrap.min.css 6527d8bf3e1e9368bab8c7b60f56bc01fa3afd68 $css_lib
		wget_verify $bootstrap_url/bootstrap.min.css.map e0d7b2bde55a0bac1b658a507e8ca491a6729e06 $css_lib
	fi
fi



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
