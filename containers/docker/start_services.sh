#!/bin/bash
echo "Starting Mail-in-a-Box services..."

service nsd start
service postfix start
dovecot # it's integration with Upstart doesn't work in docker
service opendkim start
service nginx start
service php-fastcgi start

if [ -t 0 ]
then
  # This is an interactive shell. You get a command prompt within
  # the container.
  #
  # You get here by running 'docker run -i -t'.

  echo "Welcome to your Mail-in-a-Box."
  bash

else
  # This is a non-interactive shell. It loops forever to prevent
  # the docker container from stopping.
  #
  # You get here by omitting '-t' from the docker run arguments.

  echo "Your Mail-in-a-Box is running..."
  while true; do sleep 10; done
fi
