#!/bin/bash

#Root needed
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

#Color code
yellow=`tput setaf 3`

echo "${blue}Checking local firewall status.${reset}"
ufw status verbose

#UFW CONFIGURATION
echo "${yellow}Would you like to reconfigure ufw settings? (y/n)${reset}"
read foa
if [ "$foa" = "y" ]; then
ufw allow 22
ufw allow 25
ufw allow 53
ufw allow 80
ufw allow 443
ufw allow 587
ufw allow 993
ufw allow 995
ufw allow 4190
ufw enable
fi
