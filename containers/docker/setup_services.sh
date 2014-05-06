#!/bin/bash
echo "Setting up Mail-in-a-Box services..."

SERVICES="nsd postfix dovecot opendkim nginx php-fastcgi"

for service in $SERVICES; do
    mkdir -p /etc/service/$service
done

cat <<EORUN >/etc/service/nsd/run
#!/bin/sh
exec /usr/sbin/nsd -d
EORUN

cat <<EORUN >/etc/service/postfix/run
#!/bin/sh
# from http://smarden.org/runit/runscripts.html#postfix
exec 1>&2
  
daemon_directory=/usr/lib/postfix \
  command_directory=/usr/sbin \
  config_directory=/etc/postfix \
  queue_directory=/var/spool/postfix \
  mail_owner=postfix \
  setgid_group=postdrop \
  /etc/postfix/postfix-script check || exit 1
   
exec /usr/lib/postfix/master
EORUN

cat <<EORUN >/etc/service/dovecot/run
#!/bin/sh
exec dovecot -F
EORUN

cat <<EORUN >/etc/service/opendkim/run
#!/bin/sh
exec opendkim -f -x /etc/opendkim.conf -u opendkim -P /var/run/opendkim/opendkim.pid 
EORUN

echo "daemon off;" >> /etc/nginx/nginx.conf
cat <<EORUN >/etc/service/nginx/run
#!/bin/sh
exec nginx
EORUN

cat <<EORUN >/etc/service/php-fastcgi/run
#!/bin/bash
export PHP_FCGI_CHILDREN=4 PHP_FCGI_MAX_REQUESTS=1000
exec /usr/bin/php-cgi -q -b /tmp/php-fastcgi.www-data.sock -c /etc/php5/cgi/php.ini 
EORUN

for service in $SERVICES; do
    chmod a+x /etc/service/$service/run
done

echo "Your Mail-in-a-Box services are configured."

