#!/bin/bash
# tor.sh - Yes/No
# created by Alon "ChiefGyk" Ganon
# Alon@ganon.me
# This will give the option of blocking Tor exit nodes
dialog --title "Disable Tor Exit Nodes?" \
--backtitle "" \
--yesno "Would you like to block all Tor exit nodes? This will block all traffic coming from Tor which will impair people using it to \
avoid censorship. However the majority of malicious traffic is sourced from Tor. If you change your mind later you can comment/uncomment line 13 \
of /etc/cron.daily/blacklist where it specifies Tor Exit Nodes" 15 60

# Get exit status
# 0 means user hit [yes] button.
# 1 means user hit [no] button.
# 255 means user hit [Esc] key.
response=$?
case $response in
   0) sed -e '13 s/^/#/' /etc/conf.daily/blacklist 
   echo "Tor Exit Nodes Blocked";;
   1) echo "Freedom";;
   255) echo "[ESC] key pressed.";;
esac