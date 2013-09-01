# Create a new email user.
##########################

echo
echo "Set up your first email account..."
read -e -i "user@`hostname`" -p "Email Address: " EMAIL_ADDR
read -e -p "Email Password (blank to skip): " EMAIL_PW

if [ ! -z "$EMAIL_PW" ]; then
	echo "INSERT INTO users (email, password) VALUES ('$EMAIL_ADDR', '`doveadm pw -s SHA512-CRYPT -p $EMAIL_PW`');" \
		| sqlite3 $STORAGE_ROOT/mail/users.sqlite
fi

