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
#
# The server_names_hash_bucket_size seems to prevent long domain names!
# The default, according to nginx's docs, depends on "the size of the
# processor’s cache line." It could be as low as 32. We fixed it at
# 64 in 2014 to accommodate a long domain name (20 characters?). But
# even at 64, a 58-character domain name won't work (#93), so now
# we're going up to 128.
#
# Drop TLSv1.0, TLSv1.1, following the Mozilla "Intermediate" recommendations
# at https://ssl-config.mozilla.org/#server=nginx&server-version=1.17.0&config=intermediate&openssl-version=1.1.1.
tools/editconf.py /etc/nginx/nginx.conf -s \
	server_names_hash_bucket_size="128;" \
	ssl_protocols="TLSv1.2 TLSv1.3;"

# Tell PHP not to expose its version number in the X-Powered-By header.
tools/editconf.py /etc/php/7.2/fpm/php.ini -c ';' \
	expose_php=Off

# Set PHPs default charset to UTF-8, since we use it. See #367.
tools/editconf.py /etc/php/7.2/fpm/php.ini -c ';' \
        default_charset="UTF-8"

# Configure the path environment for php-fpm
tools/editconf.py /etc/php/7.2/fpm/pool.d/www.conf -c ';' \
	env[PATH]=/usr/local/bin:/usr/bin:/bin \

# Configure php-fpm based on the amount of memory the machine has
# This is based on the nextcloud manual for performance tuning: https://docs.nextcloud.com/server/17/admin_manual/installation/server_tuning.html
# Some synchronisation issues can occur when many people access the site at once.
# The pm=ondemand setting is used for memory constrained machines < 2GB, this is copied over from PR: 1216
TOTAL_PHYSICAL_MEM=$(head -n 1 /proc/meminfo | awk '{print $2}' || /bin/true)
if [ $TOTAL_PHYSICAL_MEM -lt 1000000 ]
then
        tools/editconf.py /etc/php/7.2/fpm/pool.d/www.conf -c ';' \
                pm=ondemand \
                pm.max_children=8 \
                pm.start_servers=2 \
                pm.min_spare_servers=1 \
                pm.max_spare_servers=3
elif [ $TOTAL_PHYSICAL_MEM -lt 2000000 ]
then
        tools/editconf.py /etc/php/7.2/fpm/pool.d/www.conf -c ';' \
                pm=ondemand \
                pm.max_children=16 \
                pm.start_servers=4 \
                pm.min_spare_servers=1 \
                pm.max_spare_servers=6
elif [ $TOTAL_PHYSICAL_MEM -lt 3000000 ]
then
        tools/editconf.py /etc/php/7.2/fpm/pool.d/www.conf -c ';' \
                pm=dynamic \
                pm.max_children=60 \
                pm.start_servers=6 \
                pm.min_spare_servers=3 \
                pm.max_spare_servers=9
else
        tools/editconf.py /etc/php/7.2/fpm/pool.d/www.conf -c ';' \
                pm=dynamic \
                pm.max_children=120 \
                pm.start_servers=12 \
                pm.min_spare_servers=6 \
                pm.max_spare_servers=18
fi

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

# Create a generic mta-sts.txt file which is exposed via the
# nginx configuration at /.well-known/mta-sts.txt
# more documentation is available on: 
# https://www.uriports.com/blog/mta-sts-explained/
cat conf/mta-sts.txt \
        | sed "s/PRIMARY_HOSTNAME/$PRIMARY_HOSTNAME/" \
         > /var/lib/mailinabox/mta-sts.txt
chmod a+r /var/lib/mailinabox/mta-sts.txt

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

