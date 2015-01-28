#!/bin/bash
# Munin: resource monitoring tool
#################################################

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

# install Munin
apt_install munin munin-plugins-extra

# edit config
cat > /etc/munin/munin.conf <<EOF;
  dbdir /var/lib/munin
  htmldir /var/cache/munin/www
  logdir /var/log/munin
  rundir /var/run/munin
  tmpldir /etc/munin/templates

  includedir /etc/munin/munin-conf.d

  # a simple host tree
  [$PRIMARY_HOSTNAME]
  address 127.0.0.1
  use_node_name yes

  # send alerts to the following address
  contacts admin
  contact.admin.command mail -s "Munin notification ${var:host}" administrator@$PRIMARY_HOSTNAME
  contact.admin.always_send warning critical
EOF


# set subdomain
DOMAIN=${PRIMARY_HOSTNAME#[[:alpha:]]*.}
hide_output curl -d "" --user $(</var/lib/mailinabox/api.key): http://127.0.0.1:10222/dns/set/munin.$DOMAIN

# write nginx config
cat > /etc/nginx/conf.d/munin.conf <<EOF;
  # Redirect all HTTP to HTTPS.
  server {
    listen 80;
    listen [::]:80;

    server_name munin.$DOMAIN;
    root /tmp/invalid-path-nothing-here;
    rewrite ^/(.*)$ https://munin.$DOMAIN/$1 permanent;
  }

  server {
    listen 443 ssl;

    server_name munin.$DOMAIN;

    ssl_certificate $STORAGE_ROOT/ssl/ssl_certificate.pem;
    ssl_certificate_key $STORAGE_ROOT/ssl/ssl_private_key.pem;
    include /etc/nginx/nginx-ssl.conf;

    auth_basic "Authenticate";
    auth_basic_user_file /etc/nginx/htpasswd;

    root /var/cache/munin/www;

    location = /robots.txt {
      log_not_found off;
      access_log off;
    }
  }
EOF
