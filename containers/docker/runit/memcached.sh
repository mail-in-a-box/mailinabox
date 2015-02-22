#!/bin/sh

exec /sbin/setuser memcache /usr/bin/memcached >>/var/log/memcached.log 2>&1