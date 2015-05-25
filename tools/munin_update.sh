#!/bin/bash
# Grant admins access to munin

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

db=$STORAGE_ROOT'/mail/users.sqlite'

users=`sqlite3 $db "SELECT email FROM users WHERE privileges = 'admin'"`;
passwords=`sqlite3 $db "SELECT password FROM users WHERE privileges = 'admin'"`;

# Define the arrays
users_array=(${users// / })
passwords_array=(${passwords// / })

# clear htpasswd
>/etc/nginx/htpasswd

# write user:password
for i in "${!users_array[@]}"; do
  echo "${users_array[i]}:${passwords_array[i]:14}" >> /etc/nginx/htpasswd
done
