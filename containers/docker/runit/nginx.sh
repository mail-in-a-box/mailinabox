#!/bin/bash

exec /usr/sbin/nginx -c /etc/nginx/nginx.conf  -g "daemon off;" 2>&1
