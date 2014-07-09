# Managesieve: Manage a user's sieve script collection.
#######################################################

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars
managesieveDir=$STORAGE_ROOT/mail/managesieve

apt_install \
	dovecot-managesieved

cat - > /etc/dovecot/conf.d/90-sieve.conf << EOF;
##
## Settings for the Sieve interpreter
##
plugin {
  # The path to the user's main active script. If ManageSieve is used, this the
  # location of the symbolic link controlled by ManageSieve.
  sieve = $managesieveDir/%d/%n/.dovecot.sieve

  # Directory for :personal include scripts for the include extension. This
  # is also where the ManageSieve service stores the user's scripts.
  sieve_dir = $managesieveDir/%d/%n
}
EOF

mkdir $managesieveDir 
chown -R mail.mail  $managesieveDir

service dovecot restart
