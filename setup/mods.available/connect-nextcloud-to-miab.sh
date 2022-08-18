#!/bin/bash

#
# Run this script on your remote Nextcloud to configure it to use
# Mail-in-a-Box-LDAP.
#
# The script will:
#   1. enable the "LDAP user and group backend" in Nextcloud
#   2. install calendar and contacts
#   3. configure Nextcloud to access MiaB-LDAP for users and groups
#   4. optionally install and configure ssmtp so system mail is
#      sent to MiaB-LDAP
#
# It should be run after configuring MiaB-LDAP to use a remote
# nextcloud, which is accomplished by enabling the setup mod
# "remote-nextcloud.sh." Creating a symbolic link to
# remote-nextcloud.sh in the directory
# <miab-installation-directory>/local with the same name enables the
# mod. You'll have to re-run setup by executing setup/start.sh (or
# ehdd/start-encrypted.sh if you're using encryption-at-rest).
#

VERBOSE=0


say() {
    echo "$@"
}

say_verbose() {
    if [ $VERBOSE -gt 0 ]; then
        echo "$@"
    fi
}

die() {
    echo "$@" 1>&2
    exit 2
}

die_with_code() {
    code="$1"
    shift
    echo "$@" 1>&2
    exit $code
}


usage() {
    cat <<EOF
Usage: $0 <NCDIR> <NC_ADMIN_USER> <NC_ADMIN_PASSWORD> <MIAB_HOSTNAME> <LDAP_NEXTCLOUD_PASS> [ <SSMTP_ALERTS_EMAIL> <SSMTP_AUTH_USER> <SSMTP_AUTH_PASS> ]
Configure Nextcloud to use MiaB-LDAP for users and groups
Optionally configure a mail relay to MiaB-LDAP

Arguments:
    NCDIR               
        the path to the local Nextcloud installation directory
    NC_ADMIN_USER
        a current Nextcloud username that has ADMIN rights
    NC_ADMIN_PASSWORD         
        the password for NC_ADMIN
    MIAB_HOSTNAME       
        the fully-qualified host name of MiaB-LDAP
    LDAP_NEXTCLOUD_PASS 
        supply the password for the LDAP service account Nextcloud
        uses to locate and enumerate users and groups. A MiaB-LDAP
        installation automatically creates this limited-access service
        account with a long random password. Open
        /home/user-data/ldap/miab_ldap.conf on your MiaB-LDAP box,
        then paste the password for "$LDAP_NEXTCLOUD_DN" as a script
        argument. It will be the value of the LDAP_NEXTCLOUD_PASSWORD
        key.
    SSMTP_ALERTS_EMAIL / SSMTP_AUTH_USER / SSMTP_AUTH_PASS
        OPTIONAL. Supplying these arguments will setup ssmtp on your
        system and configure it to use MiaB-LDAP as its mail relay.
        Email sent with sendmail or ssmtp will be relayed to
        MiaB-LDAP. SSMTP_ALERTS_EMAIL is the email address that will
        receive messages for all userids less than
        1000. SSMTP_AUTH_USER / SSMTP_AUTH_PASS is the email address
        that will be used to authenticate with MiaB-LDAP (the sender
        or envelope FROM address). You probably want a new/dedicated
        email address for this - create a new account in the MiaB-LDAP
        admin interface. More information on ssmtp is available at
        https://help.ubuntu.com/community/EmailAlerts.

The script must be run as root.

EOF
    exit 1
}

miab_constants() {
    # Hostname of the remote MiaB-LDAP
    MAILINABOX_HOSTNAME="$1"

    # LDAP service account Nextcloud uses to perform ldap searches.
    # Values are found in mailinabox:/home/user-data/ldap/miab_ldap.conf
    LDAP_NEXTCLOUD_DN="cn=nextcloud,ou=Services,dc=mailinabox"
    LDAP_NEXTCLOUD_PASSWORD="$2"

    LDAP_URL="ldaps://$MAILINABOX_HOSTNAME"
    LDAP_SERVER="$MAILINABOX_HOSTNAME"
    LDAP_SERVER_PORT="636"
    LDAP_SERVER_STARTTLS="no"
    LDAP_BASE="dc=mailinabox"
    LDAP_USERS_BASE="ou=Users,dc=mailinabox"
}


test_ldap_connection() {
    say_verbose "Installing system package ldap-utils"
    apt-get install -y -qq ldap-utils || die "Could not install required packages"
    
    local count=0
    local ldap_debug=""
    
    while /bin/true; do
        # ensure we can search
        local output
        say ""
        say "Testing MiaB-LDAP connection..."
        output="$(ldapsearch $ldap_debug -v -H $LDAP_URL -x -D "$LDAP_NEXTCLOUD_DN" -w "$LDAP_NEXTCLOUD_PASSWORD" -b "$LDAP_BASE" -s base 2>&1)"
        local code=$?
        if [ $code -ne 0 ]; then
            say "Unable to contact $LDAP_URL"
            say "   base=$LDAP_BASE"
            say "   user=$LDAP_NEXTCLOUD_DN"
            say "   error code=$code"
            say "   msg= $output"
            say ""
            say "You may need to permit access to the ldap server running on $LDAP_SERVER"
            say "On $LDAP_SERVER execute:"
            local ip
            for ip in $(hostname -I); do
                say "   ufw allow proto tcp from $ip to any port ldaps"
            done
            say ""
            let count+=1
            if [ $count -gt 5 ]; then
                die "Giving up"
            fi
            if [ -z "$ldap_debug" ]; then
                echo "I'll turn on more debugging output on the next attempt"
            fi
            read -p "Press [enter] when ready, or \"no\" to give up: " ans
            [ "$ans" == "no" ] && die "Abandoning MiaB-LDAP integration"
            ldap_debug="-d 9"
            
        else
            say "Test successful - able to bind and search as $LDAP_NEXTCLOUD_DN"
            break
        fi
    done
}





if [ "$1" == "-v" ]; then
    VERBOSE=1
    shift
fi

if [ "$1" == "--test-ldap-connection" ]; then
    shift
    if [ $# -ne 2 ]; then usage; fi
    miab_constants "$1" "$2"
    test_ldap_connection
    exit 0
fi


# Directory where Nextcloud is installed (must contain occ)
NCDIR="$1"

# Nextcloud admin credentials for making user-ldap API calls via curl
NC_ADMIN_USER="$2"
NC_ADMIN_PASSWORD="$3"

# Set MiaB-LDAP constants 4=host 5=service-account-password
miab_constants "$4" "$5"

# ssmtp: the person who gets all emails for userids < 1000
SSMTP_ALERTS_EMAIL="$6"
SSMTP_AUTH_USER="$7"
SSMTP_AUTH_PASS="$8"

# other constants
PRIMARY_HOSTNAME="$(hostname --fqdn || hostname)"


#
# validate arguments
#
if [ -z "$NCDIR" -o "$1" == "-h" -o "$1" == "--help" ]
then
    usage
fi

if [ -z "$NCDIR" -o ! -d "$NCDIR" ]
then
    echo "Invalid directory: $NCDIR" 1>&2
    exit 1
fi

if [ ! -e "$NCDIR/occ" ]; then
    echo "OCC not found at: $NCDIR/occ !" 1>&2
    exit 1
fi

if [ -z "$NC_ADMIN_USER" -o \
     -z "$MAILINABOX_HOSTNAME" -o \
     -z "$LDAP_NEXTCLOUD_PASSWORD" ]
then
    usage
fi

if [ ! -z "$SSMTP_ALERTS_EMAIL" ]; then
    if [ -z "$(awk -F@ '{print $2}' <<< "$SSMTP_ALERTS_EMAIL")" ]; then
        echo "Invalid email address: $SSMTP_ALERTS_EMAIL" 1>&2
        exit 1
    fi
    if [ -z "$(awk -F@ '{print $2}' <<< "$SSMTP_AUTH_USER")" ]; then
        echo "Invalid email address: $SSMTP_AUTH_USER" 1>&2
        exit 1
    fi
fi

if [ -s /etc/mailinabox.conf ]; then
    echo "Run on your remote Nextcloud, not on Mail-in-a-Box !!" 1>&2
    exit 1
fi

if [ "$EUID" != "0" ]; then
    echo "The script must be run as root (sudo)" 1>&2
    exit 1
fi



#
# get the url used to access nextcloud as NC_ADMIN_USER
#
NC_CONFIG_CLI_URL="$(cd "$NCDIR/config"; php -n -r 'include "config.php"; print $CONFIG["overwrite.cli.url"];')"
case "$NC_CONFIG_CLI_URL" in
    http:* | https:* )
        urlproto=$(awk -F/ '{print $1}' <<< "$NC_CONFIG_CLI_URL")
        urlhost=$(awk -F/ '{print $3}'  <<< "$NC_CONFIG_CLI_URL")
        urlprefix=$(awk -F/ "{ print substr(\$0,length(\"$urlproto\")+length(\"\
$urlhost\")+4) }" <<<"$NC_CONFIG_CLI_URL")
        NC_AUTH_URL="$urlproto//${NC_ADMIN_USER}:${NC_ADMIN_PASSWORD}@$urlhost/\
$urlprefix"
        ;;
    * )
        NC_AUTH_URL="https://${NC_ADMIN_USER}:${NC_ADMIN_PASSWORD}@$PRIMARY_HOS\
TNAME${NC_CONFIG_CLI_URL:-/}"
        ;;
esac




#
# configure Nextcloud's user-ldap for MiaB-LDAP
#
# See: https://docs.nextcloud.com/server/17/admin_manual/configuration_user/user_auth_ldap_api.html
#
config_user_ldap() {
    local id="${1:-s01}"
    local first_call="${2:-yes}"
    local starttls=0
    [ "$LDAP_SERVER_STARTTLS" == "yes" ] && starttls=1

    apt-get install -y -qq python3 || die "Could not install required packages"

    local c=(
        "--data-urlencode configData[ldapHost]=$LDAP_URL"
        "--data-urlencode configData[ldapPort]=$LDAP_SERVER_PORT"
        "--data-urlencode configData[ldapBase]=$LDAP_USERS_BASE"
        "--data-urlencode configData[ldapTLS]=$starttls"
        
        "--data-urlencode configData[ldapAgentName]=$LDAP_NEXTCLOUD_DN"
        "--data-urlencode configData[ldapAgentPassword]=$LDAP_NEXTCLOUD_PASSWORD"
        
        "--data-urlencode configData[ldapUserDisplayName]=cn"
        "--data-urlencode configData[ldapUserDisplayName2]="
        "--data-urlencode configData[ldapUserFilter]=(&(objectClass=inetOrgPerson)(objectClass=mailUser))"
        "--data-urlencode configData[ldapUserFilterMode]=1"
        "--data-urlencode configData[ldapLoginFilter]=(&(objectClass=inetOrgPerson)(objectClass=mailUser)(|(mail=%uid)(uid=%uid)))"
        "--data-urlencode configData[ldapEmailAttribute]=mail"
        
        "--data-urlencode configData[ldapGroupFilter]=(objectClass=mailGroup)"
        "--data-urlencode configData[ldapGroupMemberAssocAttr]=member"
        "--data-urlencode configData[ldapGroupDisplayName]=mail"
        "--data-urlencode configData[ldapNestedGroups]=1"
        "--data-urlencode configData[turnOnPasswordChange]=1"
        
        "--data-urlencode configData[ldapExpertUsernameAttr]=maildrop"
        "--data-urlencode configData[ldapExpertUUIDUserAttr]=uid"
        "--data-urlencode configData[ldapExpertUUIDGroupAttr]=entryUUID"

        "--data-urlencode configData[ldapConfigurationActive]=1"
    )

    # apply the settings - note: we can't use localhost because nginx
    # will route to the wrong virtual host
    local xml
    say_verbose "curl \"${NC_AUTH_URL%/}/ocs/v2.php/apps/user_ldap/api/v1/config/$id\""
    xml="$(curl -s -S --insecure -X PUT "${NC_AUTH_URL%/}/ocs/v2.php/apps/user_ldap/api/v1/config/$id" -H "OCS-APIREQUEST: true" ${c[@]})"
    [ $? -ne 0 ] &&
        die "Unable to issue a REST call as $NC_ADMIN_USER to nextcloud. url=$NC_AUTH_URL/ocs/v2.php/apps/user_ldap/api/v1/config/$id"

    # did it work?
    if [ -z "$xml" ]; then
        die "Invalid response from Nextcloud using url '$NC_AUTH_URL'. reponse was '$xml'. Cannot continue."
    fi
        
    local statuscode
    statuscode=$(python3 -c "import xml.etree.ElementTree as ET; print(ET.fromstring(r'''$xml''').findall('meta')[0].findall('statuscode')[0].text)")
    
    if [ "$statuscode" == "404" -a "$first_call" == "yes" ]; then
        # got a 404 so maybe this is the first time -- we have to create
        # an initial blank ldap configuration and try again
        xml="$(curl -s -S --insecure -X POST "${NC_AUTH_URL%/}/ocs/v2.php/apps/user_ldap/api/v1/config" -H "OCS-APIREQUEST: true")"
        [ $? -ne 0 ] &&
            die "Unable to issue a REST call as $NC_ADMIN_USER to nextcloud: $xml"
        statuscode=$(python3 -c "import xml.etree.ElementTree as ET; print(ET.fromstring(r'''$xml''').findall('meta')[0].findall('statuscode')[0].text)")
        [ $? -ne 0 -o "$statuscode" != "200" ] &&
            die "Error creating initial ldap configuration: $xml"
        
        id=$(python3 -c "import xml.etree.ElementTree as ET; print(ET.fromstring(r'''$xml''').findall('data')[0].findall('configID')[0].text)" 2>/dev/null)
        [ $? -ne 0 ] &&
            die "Error creating initial ldap configuration: $xml"
        
        config_user_ldap "$id" no

    elif [ "$statuscode" == "997" -a "$first_call" == "yes" ]; then
        # could not log in
        die_with_code 3 "Could not authenticate as $NC_ADMIN_USER to perform user-ldap API call. statuscode=$statuscode: $xml"
        
    elif [ "$statuscode" != "200" ]; then
        die "Unable to apply ldap configuration to nextcloud: id=$id first_call=$first_call statuscode=$statuscode: $xml"
    fi
    return 0
}



enable_user_ldap() {
    # install prerequisite package php-ldap
    # if using Docker Hub's php image, don't install at all
    
    if [ ! -e /etc/apt/preferences.d/no-debian-php ]; then        
        # on a cloud-in-a-box installation, get the php version that
        # nextcloud uses, otherwise install the system php
        local php="php"
        local ciab_site_conf="/etc/nginx/sites-enabled/cloudinabox-nextcloud"
        if [ -e "$ciab_site_conf" ]; then
            php=$(grep 'php[0-9].[0-9]-fpm.sock' "$ciab_site_conf" | \
                      awk '{print $2}' | \
                      awk -F/ '{print $NF}' | \
                      sed 's/-fpm.*$//')
            if [ $? -ne 0 ]; then
                say "Warning: this looks like a Cloud-In-A-Box system, but detecting the php version used by Nextcloud failed. Using the system php-ldap module..."
                php="php"
            fi
        fi
        say_verbose "Installing system package $php-ldap"
        apt-get install -y -qq $php-ldap || die "Could not install $php-ldap package"
        #restart_service $php-fpm
    fi
    
    # enable user_ldap
    if [ ! -x /usr/bin/sudo ]; then
        say "WARNING: sudo is not installed: Unable to run occ to check and/or enable Nextcloud app \"user-ldap\"."
    else
        say_verbose "Enable user-ldap"
        sudo -E -u www-data php $NCDIR/occ app:enable user_ldap -q
        [ $? -ne 0 ] && die "Unable to enable user_ldap nextcloud app"
    fi
}

install_app() {
    local app="$1"
    if [ ! -x /usr/bin/sudo ]; then
        say "WARNING: sudo is not installed: Unable to run occ to check and/or install Nextcloud app \"$app\"."
        
    elif [ -z "$(sudo -E -u www-data php $NCDIR/occ app:list | grep -F $app:)" ]; then
        say_verbose "Install app '$app'"
        sudo -E -u www-data php $NCDIR/occ app:install $app
        [ $? -ne 0 ] && die "Unable to install Nextcloud app '$app'"
    fi
}


setup_ssmtp() {
    # sendmail-like mailer with a mailhub to remote mail-in-a-box
    # see: https://help.ubuntu.com/community/EmailAlerts

    if [ "$(. /etc/os-release; echo $NAME)" != "Ubuntu" ]; then
        die "Sorry, ssmtp is only supported on Ubuntu"
    fi
    
    say_verbose "Installing system package ssmtp"
    apt-get install -y -qq ssmtp

    if [ ! -e /etc/ssmtp/ssmtp.conf.orig ]; then
        cp /etc/ssmtp/ssmtp.conf /etc/ssmtp/ssmtp.conf.orig
    fi
    
    cat <<EOF >/etc/ssmtp/ssmtp.conf
# Generated by MiaB-LDAP integration script on $(date)

# The person who gets all mail for userids < 1000
root=${SSMTP_ALERTS_EMAIL}

# The place where mail goes
mailhub=${MAILINABOX_HOSTNAME}:587
AuthUser=${SSMTP_AUTH_USER}
AuthPass=${SSMTP_AUTH_PASS}
UseTLS=YES
UseSTARTTLS=YES

# The full hostname
hostname=${PRIMARY_HOSTNAME}

# Are users allowed to set their own From address?
FromLineOverride=YES
EOF
}



remote_mailinabox_handler() {
    test_ldap_connection
    enable_user_ldap
    config_user_ldap
    return 0
}



echo "Integrating Nextcloud with Mail-in-a-box LDAP"
remote_mailinabox_handler || die "Unable to continue"

# contacts and calendar are required for Roundcube and Z-Push
install_app "calendar"
install_app "contacts"

if [ ! -z "${SSMTP_ALERTS_EMAIL}" ]; then
    setup_ssmtp
fi

say ""
say "Done!"
