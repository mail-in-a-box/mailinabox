#!/bin/bash

# Simple script to update the mail app in ownCloud, not needed once it reaches beta+

echo "installing mail app..."
rm -f /tmp/owncloud_mail.zip
wget -qO /tmp/owncloud_mail.zip https://github.com/owncloud/mail/archive/master.zip
unzip /tmp/owncloud_mail.zip -d /usr/local/lib/owncloud/apps
mv /usr/local/lib/owncloud/apps/mail-master /usr/local/lib/owncloud/apps/mail
rm -f /tmp/owncloud.zip

echo "installing php composer and mail app dependencies..."
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/lib/owncloud/apps/mail
php /usr/local/lib/owncloud/apps/mail/composer.phar install --working-dir=/usr/local/lib/owncloud/apps/mail
chmod -R 777 /usr/local/lib/owncloud/apps/mail/vendor/ezyang/htmlpurifier/library/HTMLPurifier/DefinitionCache/Serializer

echo "DONE! :-)"