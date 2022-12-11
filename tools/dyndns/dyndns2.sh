#!/bin/bash
# based on dm-dyndns v1.0, dmurphy@dmurphy.com
# Shell script to provide dynamic DNS to a mail-in-the-box platform.
# Requirements:
# curl installed
# oathtool installed if totp is to be used
# OpenDNS myip service availability (myip.opendns.com 15)
# Mailinabox host (see https://mailinabox.email 2)
# Mailinabox admin username/password in the CFGFILE below
# one line file of the format (curl cfg file):
# user = “username:password”
# Dynamic DNS name to be set
# DYNDNSNAMELIST file contains one hostname per line that needs to be set to this IP.

#----- Contents of dyndns.cfg file below ------
#----- user credentials -----------------------
#USER_NAME="admin@mydomain.com"
#USER_PASS="MYADMINPASSWORD"
#----- Contents of dyndns.domain below --------
#<miabdomain.tld> 
#------ Contents of dyndns.dynlist below ------
#vpn.mydomain.com
#nas.mydomain.com
#------ Contents of dyndns.totp ---------------
#- only needed in case of TOTP authentication -
#TOTP_KEY=ABCDEFGABCFEXXXXXXXX

MYNAME="dyndns"
CFGFILE="$MYNAME.cfg"
TOTPFILE="$MYNAME.totp"
DOMFILE="$MYNAME.domain"
CURLCMD="/usr/bin/curl"
DIGCMD="/usr/bin/dig"
CATCMD="/bin/cat"
OATHTOOLCMD="/usr/bin/oathtool"
DYNDNSNAMELIST="$MYNAME.dynlist"

IGNORESTR=";; connection timed out; no servers could be reached"

if [ ! -x $CURLCMD ]; then
  echo "$MYNAME: curl command $CURLCMD not found.  Check and fix please."
  exit 99
fi

if [ ! -x $DIGCMD ]; then
  echo "$MYNAME: dig command $DIGCMD not found.  Check and fix please."
  exit 99
fi

if [ ! -x $CATCMD ]; then
  echo "$MYNAME: cat command $CATCMD not found.  Check and fix please."
  exit 99
fi

DOMAIN=$(cat $DOMFILE)
MIABHOST="box.$DOMAIN"

noww="$(date +"%F %T")"
echo "$noww: running dynamic dns update for $DOMAIN"

if [ ! -f $CFGFILE ]; then
  echo "$MYNAME: $CFGFILE not found.  Check and fix please."
  exit 99
fi

if [ ! -f $DYNDNSNAMELIST ]; then
   echo "$MYNAME: $DYNDNSNAMELIST not found.  Check and fix please."
   exit 99
fi

source $CFGFILE
AUTHSTR="Authorization: Basic $(echo $USER_NAME:$USER_PASS | base64 -w 0)"

# Test an IP address for validity:
# Usage:
#      valid_ipv4 IP_ADDRESS
#      if [[ $? -eq 0 ]]; then echo good; else echo bad; fi
#   OR
#      if valid_ipv4 IP_ADDRESS; then echo good; else echo bad; fi
#
function valid_ipv4()
{
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

MYIP="`$CURLCMD -4 -s icanhazip.com`"

if [[ "`valid_ipv4 ${MYIP}`" -ne 0 ]]; then
    MYIP="`$CURLCMD -4 -s api64.ipify.org`"
fi    

if [[ "`valid_ipv4 ${MYIP}`" -eq 0 ]]; then
  for DYNDNSNAME in `$CATCMD $DYNDNSNAMELIST`
  do
    PREVIP="`$DIGCMD A +short $DYNDNSNAME @$MIABHOST`"
    if [ -z "$PREVIP" ]; then
      echo "$MYNAME: dig output was blank."
    fi

    if [ "x$PREVIP" == "x$MYIP" ]; then
      echo "$MYNAME: $DYNDNSNAME ipv4 hasn't changed."
    else
      echo "$MYNAME: $DYNDNSNAME changed (previously: $PREVIP, now: $MYIP)"
    
      STATUS="`$CURLCMD -X PUT -u $USER_NAME:$USER_PASS -s -d $MYIP https://$MIABHOST/admin/dns/custom/$DYNDNSNAME/A`"
    
      case $STATUS in
         "OK") echo "$MYNAME: mailinabox API returned OK, cmd succeeded but no update.";;
         "updated DNS: $DOMAIN") echo "$MYNAME: mailinabox API updated $DYNDNSNAME ipv4 OK.";;
         "invalid-totp-token"|"missing-totp-token") echo "$MYNAME: invalid TOTP token. Retrying with TOTP token"
           if [ ! -x $AOTHTOOLCMD ]; then
             echo "$MYNAME: oathtool command $OATHTOOLCMD not found.  Check and fix please."
             exit 99
           fi
  
           if [ ! -f $TOTPFILE ]; then
             echo "$MYNAME: $TOTPFILE not found.  Check and fix please."
             exit 99
           fi
      
           source $TOTPFILE
  
           TOTP="X-Auth-Token: $(oathtool --totp -b -d 6 $TOTP_KEY)"
           STATUST="`$CURLCMD -X PUT -u $USER_NAME:$USER_PASS -H "$TOTP" -s -d $MYIP https://$MIABHOST/admin/dns/custom/$DYNDNSNAME/A`"
           
           case $STATUST in
             "OK") echo "$MYNAME: mailinabox API returned OK, cmd succeeded but no update.";;
             "updated DNS: $DOMAIN") echo "$MYNAME: mailinabox API updated $DYNDNSNAME ipv4 OK.";;
             "invalid-totp-token") echo "$MYNAME: invalid TOTP token.";;
             *) echo "$MYNAME: other status from mailinabox API. Please check: $STATUST (2)";;
           esac
           ;;
         *) echo "$MYNAME: other status from mailinabox API. Please check: $STATUS (1)";;
      esac
    fi
  done
else
  echo "$MYNAME: No ipv4 address found."
fi

# Now to do the same for ipv6

function valid_ipv6()
{
    local IP_ADDR=$1
    local stat=1
    
    if python3 -c "import ipaddress; ipaddress.IPv6Network('${IP_ADDR}')" 2>/dev/null; then
        stat=0
    fi
    return $stat
}

MYIP="`$CURLCMD -6 -s icanhazip.com`"

if [[ "`valid_ipv6 ${MYIP}`" -ne 0 ]]; then
    MYIP="`$CURLCMD -6 -s api64.ipify.org`"
fi    

if [[ "`valid_ipv6 ${MYIP}`" -eq 0 ]]; then
  for DYNDNSNAME in `$CATCMD $DYNDNSNAMELIST`
  do
    PREVIP="`$DIGCMD AAAA +short $DYNDNSNAME @$MIABHOST`"
    if [ -z "$PREVIP" ]; then
      echo "$MYNAME: dig output was blank."
    fi

    if [ "x$PREVIP" = "x$MYIP" ]; then
      echo "$MYNAME: $DYNDNSNAME ipv6 hasn't changed."
    else
      echo "$MYNAME: $DYNDNSNAME changed (previously: $PREVIP, now: $MYIP)"
    
      STATUS="`$CURLCMD -X PUT -u $USER_NAME:$USER_PASS -s -d $MYIP https://$MIABHOST/admin/dns/custom/$DYNDNSNAME/AAAA`"
    
      case $STATUS in
         "OK") echo "$MYNAME: mailinabox API returned OK, cmd succeeded but no update.";;
         "updated DNS: $DOMAIN") echo "$MYNAME: mailinabox API updated $DYNDNSNAME ipv6 OK.";;
         "invalid-totp-token"|"missing-totp-token") echo "$MYNAME: invalid TOTP token. Retrying with TOTP token"
           if [ ! -x $AOTHTOOLCMD ]; then
             echo "$MYNAME: oathtool command $OATHTOOLCMD not found.  Check and fix please."
             exit 99
           fi
  
           if [ ! -f $TOTPFILE ]; then
             echo "$MYNAME: $TOTPFILE not found.  Check and fix please."
             exit 99
           fi
      
           source $TOTPFILE
  
           TOTP="X-Auth-Token: $(oathtool --totp -b -d 6 $TOTP_KEY)"
           STATUST="`$CURLCMD -X PUT -u $USER_NAME:$USER_PASS -H "$TOTP" -s -d $MYIP https://$MIABHOST/admin/dns/custom/$DYNDNSNAME/AAAA`"
           
           case $STATUST in
             "OK") echo "$MYNAME: mailinabox API returned OK, cmd succeeded but no update.";;
             "updated DNS: $DOMAIN") echo "$MYNAME: mailinabox API updated $DYNDNSNAME ipv6 OK.";;
             "invalid-totp-token") echo "$MYNAME: invalid TOTP token.";;
             *) echo "$MYNAME: other status from mailinabox API. Please check: $STATUST (2)";;
           esac
           ;;
         *) echo "$MYNAME: other status from mailinabox API. Please check: $STATUS (1)";;
      esac
    fi
  done
else
  echo "$MYNAME: No ipv6 address found."
  exit 99
fi

exit 0

