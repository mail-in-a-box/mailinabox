#!/bin/bash

HEIGHT=30
WIDTH=80
CHOICE_HEIGHT=4
BACKTITLE="Do you want to block China and/or Korea?"
TITLE="Country Block"
MENU="A lot of spam, as well as malicious traffic originates from Korea and China. If you don't plan on having to ever have those countries connect to your server you may block them.
	This will add a cron that will update weekly, and block all IP blocks to those countries you choose
	Choose one of the following options:"

OPTIONS=(1 "China"
         2 "Korea"
         3 "China and Korea"
		 4 "Do nothing")

CHOICE=$(dialog --clear \
                --backtitle "$BACKTITLE" \
                --title "$TITLE" \
                --menu "$MENU" \
                $HEIGHT $WIDTH $CHOICE_HEIGHT \
                "${OPTIONS[@]}" \
                2>&1 >/dev/tty)

clear
case $CHOICE in
        1)
            echo "Are you Donald Trump?"
			echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
			echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
			cp conf/china /etc/cron.weekly/china
			chmod +x /etc/cron.weekly/china
			time /etc/cron.weekly/china
			apt-get install -y iptables-persistent
            ;;
        2)
            echo "Starting the Korean war again"
			echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
			echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
			cp conf/korea /etc/cron.weekly/korea
			chmod +x /etc/cron.weekly/korea
			time /etc/cron.weekly/korea
			apt-get install -y iptables-persistent
            ;;
        3)
            echo "Blocking almost 1/3 of the world"
			echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
			echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
			cp conf/sinokorea /etc/cron.weekly/sinokorea
			chmod +x /etc/cron.weekly/sinokorea
			time /etc/cron.weekly/sinokorea
			apt-get install -y iptables-persistent
            ;;
		4) echo "doing nothing"
		;;
esac