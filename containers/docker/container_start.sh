#!/bin/bash

# The PUBLIC_HOSTNAME and PUBLIC_IP is not known at the time the docker
# image is built. On the first run of the container, re-run the start
# script with actual values. That will also ask the user for their first
# email user account.
if grep "^PUBLIC_IP=192.168.200.1" /etc/mailinabox.conf > /dev/null; then
  echo "Configuring container on first run..."

  # Get the public IP address of the host machine.
  export PUBLIC_IP=`curl -s icanhazip.com`
  echo Your IP address is $PUBLIC_IP.

  # Get the reverse DNS of that IP address.
  export PUBLIC_HOSTNAME=`host $PUBLIC_IP | sed -e "s/.* //" | sed -e "s/\.$//"`
  echo Your hostname is $PUBLIC_HOSTNAME.

  # Start configuration again. Hide the terminal. The system services
  # have not been started yet, so we can't ask the user to create an
  # account yet.
  cd /usr/local/mailinabox
  setup/start.sh < /dev/null
fi

