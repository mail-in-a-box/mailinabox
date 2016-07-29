#!/bin/bash
#
# This allows for resetting the password for
# access to Rainloop's Admin panel:
# https://yourdomain.com/mail/?admin
# 

source /etc/mailinabox.conf


echo "Tool for resetting Rainloop Admin Password"
echo
echo "Password must be 8 characters or longer."
echo 
echo -n "Please provide a new admin password (ctrl-c to cancel):"
read -s newpassword
echo

if [ -z $newpassword ]
then
    echo "Error: Password can not be blank."
    exit 1
fi

if [ ${#newpassword} -lt 8 ]
then
    echo "Error: Password length must be 8 characters or longer."
    exit 1
fi


echo "<?php

\$_ENV['RAINLOOP_INCLUDE_AS_API'] = true;
include '/usr/local/lib/rainloop/index.php';

\$oConfig = \RainLoop\Api::Config();
\$oConfig->SetPassword('$newpassword');
echo \$oConfig->Save() ? 'Done' : 'Error';

?>" | /usr/bin/php

echo ""
echo "Login to Rainloop Admin Panel here using your new password:"
echo "Username: admin"
echo "https://$PRIMARY_HOSTNAME/mail/?admin"
