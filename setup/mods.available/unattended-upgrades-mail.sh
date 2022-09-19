#!/bin/bash
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####


# Created by: downtownallday

#
# This mod will configure ubuntu's "unattended-upgrades" package to
# send email whenever unattended upgrades fail.
#
# When enabling the mod on a mailinabox-ldap installation, you must be
# able to receive mail from root by creating an alias "root@<miab-ldap
# host>" directed to "administrator@<miab-ldap host>" using the admin
# console.
#
# you can confirm this by running as root on miab-ldap:
#
#   setup/ldap.sh -search "(mail=root@$(hostname --fqdn))"
#
# should return something like this:
#   dn: cn=b6e5b8cb-78b1-4051-a482-36ef792edae9,ou=aliases,ou=Users,dc=mailinabox
#   mail: root@mail.mydomain.com
#   cn: b6e5b8cb-78b1-4051-a482-36ef792edae9
#   mailMember: administrator@mail.mydomain.com
#   description: Local root mail
#   objectClass: mailGroup
#   objectClass: namedProperties
#
#
# When enabling the mod on a cloudinabox installation:
#
#   a. the ssmtp package must be installed and working (typically it
#      has already been configured by setup)
#   b. a smart host setup in mailinabox-ldap must be configured so
#      that mail from cloudinabox will be accepted.
#
# Configuring a smart host is accomplished by creating a catch-all
# alias "@<cloudinabox-host>" with a permitted sender list containing
# the email address that ssmtp is using to authenticate with. The
# forward-to field is empty.
#
# eg. assuming "cloud.mydomain.com" is the hostname of your
# cloudinabox, and "alerts@mydomain.com" is the email address that
# ssmtp is using to authenticate with mailinabox-ldap (see
# /etc/ssmtp/ssmtp.conf), then running this on mailinabox-ldap:
#
#   setup/ldap.sh -search "(mail=@cloud.mydomain.com)"
#
# should return two entries that look something like these:
#   dn: cn=d7a41a6b-7c7c-4a36-8298-aa11875051db,ou=aliases,ou=Users,dc=mailinabox
#   mail: @cloud.mydomain.com
#   cn: d7a41a6b-7c7c-4a36-8298-aa11875051db
#   description: Smart host setup
#   objectClass: mailGroup
#   objectClass: namedProperties
#
#   dn: cn=03cb077c-ea40-5de1-f656-dc1a321775f8,ou=permitted-senders,ou=Config,dc=mailinabox
#   mail: @cloud.mydomain.com
#   description: Permitted to MAIL FROM this address
#   objectClass: mailGroup
#   cn: 03cb077c-ea40-5de1-f656-dc1a321775f8
#   member: alerts@mydomain.com
#   #^ uid=c2994711-e92f-5d91-bca7-7995ea66de52,ou=Users,dc=mailinabox
#
#
# To remove this mod, manually edit
# /etc/apt/apt.conf.d/50unattended-upgrades and comment out the line
# "Unattended-Upgrade::Mail"
#

source setup/functions.sh # load our functions
source /etc/os-release

changed=false
conf="/etc/apt/apt.conf.d/50unattended-upgrades"

# install the "mailx" mail client, which is required by the
# unattended-upgrades script.

if [ ! -x /usr/bin/mailx ]; then
    apt_install bsd-mailx
    changed=true
fi

# configure unattended-upgrades to email whenever there is an
# error. Do not overwrite existing settings.

if ! grep -E "^Unattended-Upgrade::Mail\s+" "$conf" >/dev/null
then
    tools/editconf.py "$conf" -s 'Unattended-Upgrade::Mail="root";'
    changed=true
fi


if [ "$VERSION_CODENAME" = "bionic" ]; then
    # Ubuntu 18 (bionic)
    if ! grep -E "^Unattended-Upgrade::MailOnlyOnError\s+" "$conf" >/dev/null
    then
        tools/editconf.py "$conf" -s \
            'Unattended-Upgrade::MailOnlyOnError="true";'
        changed=true
    fi
    
else
    if ! grep -E "^Unattended-Upgrade::MailReport\s+" "$conf" >/dev/null
    then
        # besides "only-on-error", other options are "always" and "on-change"
        tools/editconf.py "$conf" -s \
            'Unattended-Upgrade::MailReport="only-on-error";'
        changed=true
    fi
fi


if $changed; then
    echo "Unattended-upgrades setup mod: email notifications have been enabled"
fi

