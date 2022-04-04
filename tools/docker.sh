#!/bin/bash

# Fixup some dependencies missing from the ubuntu:bionic image
apt install locales curl lsb-release net-tools git grep -y

cd ~
git clone https://github.com/kaibae19/mailinabox

# The setup script will fail to find the IP addresses of the container
ifconfig | grep inet6 | grep global
ifconfig | grep inet | grep -v 127
echo "Export PRIVATE_IP and PUBLIC_IPV6 as variables before launching the setup script."

cd ~/mailinabox
