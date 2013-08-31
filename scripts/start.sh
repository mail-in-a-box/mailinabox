# Check system setup.
if grep -q "^PasswordAuthentication yes" /etc/ssh/sshd_config \
 || ! grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config ; then
        echo
        echo "The SSH server on this machine permits password-based login."
        echo "Add your SSH public key to $HOME/.ssh/authorized_keys, check"
        echo "check that you can log in without a password, set the option"
        echo "'PasswordAuthentication no' in /etc/ssh/sshd_config, and then"
	echo "restart the machine."
        exit
fi

# Gather information from the user.
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
	mkdir -p $STORAGE_ROOT
fi

. scripts/system.sh
. scripts/dns.sh
. scripts/mail.sh
. scripts/dkim.sh
. scripts/spamassassin.sh
. scripts/dns_update.sh
. scripts/add_mail_user.sh
. scripts/users_update.sh
