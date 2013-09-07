# HTTP: Turn on a web server serving static files
#################################################

apt-get install -q -y \
	nginx

rm -f /etc/nginx/sites-enabled/default

STORAGE_ROOT_ESC=$(echo $STORAGE_ROOT|sed 's/[\\\/&]/\\&/g')
PUBLIC_HOSTNAME_ESC=$(echo $PUBLIC_HOSTNAME|sed 's/[\\\/&]/\\&/g')

cat conf/nginx.conf \
	| sed "s/\$STORAGE_ROOT/$STORAGE_ROOT_ESC/g" \
	| sed "s/\$PUBLIC_HOSTNAME/$PUBLIC_HOSTNAME_ESC/g" \
	> /etc/nginx/conf.d/local.conf

mkdir -p $STORAGE_ROOT/www/static

service nginx restart

conf/php-fcgid start

ufw allow http
ufw allow https

