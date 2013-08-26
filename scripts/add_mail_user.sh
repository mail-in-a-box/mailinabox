EMAIL_ADDR=$1
if [ -z "$EMAIL_ADDR" ]; then
	echo
	echo "Set up your first email account..."
        read -e -i "user@`hostname`" -p "Email Address: " EMAIL_ADDR
fi

EMAIL_PW=$2
if [ -z "$EMAIL_PW" ]; then
        read -e -p "Email Password: " EMAIL_PW
fi

echo "INSERT INTO users (email, password) VALUES ('$EMAIL_ADDR', '`sudo doveadm pw -s SHA512-CRYPT -p $EMAIL_PW`');" \
	| sqlite3 $STORAGE_ROOT/mail/users.sqlite

