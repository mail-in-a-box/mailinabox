if [ -z "$PUBLIC_HOSTNAME" ]; then
	echo
	echo "Enter the hostname you want to assign to this machine."
	echo "We've guessed a value. Just backspace it if it's wrong."
	echo "Josh uses box.occams.info as his hostname. Yours should"
	echo "be similar."
	read -e -i "`hostname`" -p "Hostname: " PUBLIC_HOSTNAME
fi

if [ -z "$PUBLIC_IP" ]; then
	echo
	echo "Enter the public IP address of this machine, as given to"
	echo "you by your ISP. We've guessed a value, but just backspace"
	echo "it if it's wrong."
	read -e -i "`hostname -i`" -p "Public IP: " PUBLIC_IP
fi

if [ -z "$STORAGE_ROOT" ]; then
	if [ ! -d /home/user-data ]; then useradd -m user-data; fi
	STORAGE_ROOT=/home/user-data
fi

. scripts/system.sh
. scripts/dns.sh
. scripts/mail.sh
. scripts/dkim.sh
. scripts/spamassassin.sh
. scripts/dns_update.sh
. scripts/add_mail_user.sh
. scripts/users_update.sh
