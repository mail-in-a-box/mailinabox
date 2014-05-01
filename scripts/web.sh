# HTTP: Turn on a web server serving static files
#################################################

source scripts/functions.sh # load our functions

# Remove Apache before installing Nginx. Apache may leave
# some unwanted configuration files around (e.g. a ufw
# application config), so purge the packages.
apt-get purge -q -y apache2 apache2.2-common

apt_install nginx php5-cgi

rm -f /etc/nginx/sites-enabled/default

STORAGE_ROOT_ESC=$(echo $STORAGE_ROOT|sed 's/[\\\/&]/\\&/g')
PUBLIC_HOSTNAME_ESC=$(echo $PUBLIC_HOSTNAME|sed 's/[\\\/&]/\\&/g')

# copy in the nginx configuration file and substitute some
# variables
cat conf/nginx.conf \
	| sed "s/\$STORAGE_ROOT/$STORAGE_ROOT_ESC/g" \
	| sed "s/\$PUBLIC_HOSTNAME/$PUBLIC_HOSTNAME_ESC/g" \
	> /etc/nginx/conf.d/local.conf
cp conf/nginx-ssl.conf /etc/nginx/nginx-ssl.conf

# make a default homepage
mkdir -p $STORAGE_ROOT/www/static
cp conf/www_default.html $STORAGE_ROOT/www/static/index.html
chown -R $STORAGE_USER $STORAGE_ROOT/www/static/index.html

# Create an init script to start the PHP FastCGI daemon and keep it
# running after a reboot. Allows us to serve Roundcube for webmail.
rm -f /etc/init.d/php-fastcgi
ln -s $(pwd)/conf/phpfcgi-initscript /etc/init.d/php-fastcgi
update-rc.d php-fastcgi defaults

# Start services.
service nginx restart
service php-fastcgi restart

# Open ports.
ufw allow http
ufw allow https

