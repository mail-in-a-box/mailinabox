# HTTP: Turn on a web server serving static files
#################################################

apt-get install -q -y \
	nginx

rm -f /etc/nginx/sites-enabled/default

STORAGE_ROOT_ESC=$(echo $STORAGE_ROOT|sed 's/[\\\/&]/\\&/g')
PUBLIC_HOSTNAME_ESC=$(echo $PUBLIC_HOSTNAME|sed 's/[\\\/&]/\\&/g')

# copy in the nginx configuration file and substitute some
# variables
cat conf/nginx.conf \
	| sed "s/\$STORAGE_ROOT/$STORAGE_ROOT_ESC/g" \
	| sed "s/\$PUBLIC_HOSTNAME/$PUBLIC_HOSTNAME_ESC/g" \
	> /etc/nginx/conf.d/local.conf

# make a default homepage
mkdir -p $STORAGE_ROOT/www/static
cp conf/www_default.html $STORAGE_ROOT/www/static/index.html
chown -R $STORAGE_USER $STORAGE_ROOT/www/static/index.html

service nginx restart

conf/php-fcgid start

ufw allow http
ufw allow https

