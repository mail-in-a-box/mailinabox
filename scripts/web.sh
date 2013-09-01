# HTTP: Turn on a web server serving static files
#################################################

apt-get install -q -y nginx

rm -f /etc/nginx/sites-enabled/default.conf

cat conf/nginx.conf \
	| sed "s/\$STORAGE_ROOT/$STORAGE_ROOT/g" \
	| sed "s/\$PUBLIC_HOSTNAME/$PUBLIC_HOSTNAME/g" \
	> /etc/nginx/sites-enabled/local.conf

service nginx reload

ufw allow http
ufw allow https

