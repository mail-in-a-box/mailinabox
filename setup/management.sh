#!/bin/bash

source setup/functions.sh

apt_install python3-flask links

# Link the management server daemon into a well known location.
rm -f /usr/bin/mailinabox-daemon
ln -s `pwd`/management/daemon.py /usr/bin/mailinabox-daemon

# Create an init script to start the management daemon and keep it
# running after a reboot.
rm -f /etc/init.d/mailinabox
ln -s $(pwd)/conf/management-initscript /etc/init.d/mailinabox
update-rc.d mailinabox defaults

# Start it.
service mailinabox restart
