# Install dovecot sieve scripts to automatically move spam into the Spam folder.

db_path=$STORAGE_ROOT/mail/users.sqlite

for user in `echo "SELECT email FROM users;" | sqlite3 $db_path`; do
	maildir=`echo $user | sed "s/\(.*\)@\(.*\)/\2\/\1/"`
	
	# Write the sieve file to move mail classified as spam into the spam folder.
	mkdir -p $STORAGE_ROOT/mail/mailboxes/$maildir; # in case user has not received any mail
	cat > $STORAGE_ROOT/mail/mailboxes/$maildir/.dovecot.sieve << EOF;
require ["regex", "fileinto", "imap4flags"];

if allof (header :regex "X-Spam-Status" "^Yes") {
  setflag "\\\\Seen";
  fileinto "Spam";
  stop;
}
EOF


done

