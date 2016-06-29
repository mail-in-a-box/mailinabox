# Add multiple lists of malicious IP Addresses by Daily Crontab
# Also makes ipset and iptables persistent upon reboot
# Added by Alon "ChiefGyk" Ganon
# alonganon.info
# alon@ganon.me

# Are we running as root?
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root. Please re-run like this:"
	echo
	echo "sudo $0"
	echo
	exit
fi
apt-get update
apt-get install -y ipset dialog
mkdir /etc/ipset
ipset create blacklist hash:net
iptables -I INPUT -m set --match-set blacklist src -j DROP
cp conf/blacklist /etc/cron.daily/blacklist
chmod a+x /etc/cron.daily/blacklist
time /etc/cron.daily/blacklist
source conf/dialog.sh
#cp conf/dshield /etc/cron.daily/dshield
#chmod +x /etc/cron.daily/dshield
#time /etc/cron.daily/blacklist
iptables-save > /etc/iptables.up.rules
sed -i -e "\$apre-up ipset restore < /etc/ipset.up.rules" /etc/network/interfaces
sed -i -e "\$apre-up iptables-restore < /etc/iptables.up.rules" /etc/network/interfaces
echo "Blacklist has been installed. It will run daily automatically."
