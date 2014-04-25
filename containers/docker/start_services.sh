#!/bin/bash
echo "Starting Mail-in-a-Box services..."

service nsd start
service postfix start
dovecot # it's integration with Upstart doesn't work in docker
service opendkim start
service nginx start
service php-fastcgi start

echo "Your Mail-in-a-Box is running."
bash
