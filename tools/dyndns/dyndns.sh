#!/bin/bash
# based on dm-dyndns v1.0, dmurphy@dmurphy.com
# Shell script to provide dynamic DNS to a mail-in-the-box platform.
# Requirements:
# dig installed
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
DIGCMD="/usr/bin/dig"
CURLCMD="/usr/bin/curl"
CATCMD="/bin/cat"
OATHTOOLCMD="/usr/bin/oathtool"
DYNDNSNAMELIST="$MYNAME.dynlist"

IGNORESTR=";; connection timed out; no servers could be reached"

if [ ! -x $DIGCMD ]; then
  echo "$MYNAME: dig command $DIGCMD not found.  Check and fix please."
  exit 99
fi

if [ ! -x $CURLCMD ]; then
  echo "$MYNAME: curl command $CURLCMD not found.  Check and fix please."
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

MYIP="`$DIGCMD +short myip.opendns.com @resolver1.opendns.com`"

if [ -z "$MYIP" ]; then
  MYIP="`$DIGCMD +short myip.opendns.com @resolver2.opendns.com`"
fi

if [ "$MYIP" = "$IGNORESTR" ]; then
  MYIP=""
fi

if [ -z "$MYIP" ]; then
  MYIP="`$DIGCMD +short myip.opendns.com @resolver3.opendns.com`"
fi

if [ "$MYIP" = "$IGNORESTR" ]; then
  MYIP=""
fi

if [ -z "$MYIP" ]; then
  MYIP="`$DIGCMD +short myip.opendns.com @resolver4.opendns.com`"
fi

if [ "$MYIP" = "$IGNORESTR" ]; then
  MYIP=""
fi

if [ -z "$MYIP" ]; then
  MYIP=$($DIGCMD -4 +short TXT o-o.myaddr.l.google.com @ns1.google.com | tr -d '"')
fi

if [ "$MYIP" = "$IGNORESTR" ]; then
  MYIP=""
fi

if [ ! -z "$MYIP" ]; then
  for DYNDNSNAME in `$CATCMD $DYNDNSNAMELIST`
  do
    PREVIP="`$DIGCMD A +short $DYNDNSNAME @$MIABHOST`"
    if [ -z "$PREVIP" ]; then
      echo "$MYNAME: dig output was blank."
    fi

    if [ "x$PREVIP" = "x$MYIP" ]; then
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
             "OK") echo "$MYNAME: mailinabox API returned OK, cmd succeded but no update.";;
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
  echo "$MYNAME: No ipv4 address found. Check myaddr.google and myip.opendns.com services."
  exit 99
fi


# Now to do the same for ipv6

MYIP="`$DIGCMD +short AAAA @resolver1.ipv6-sandbox.opendns.com myip.opendns.com -6`"

if [ "$MYIP" = "$IGNORESTR" ]; then
  MYIP=""
fi

if [ -z "$MYIP" ]; then
  MYIP="`$DIGCMD +short AAAA @resolver2.ipv6-sandbox.opendns.com myip.opendns.com -6`"
fi

if [ "$MYIP" = "$IGNORESTR" ]; then
  MYIP=""
fi

if [ -z "$MYIP" ]; then
  MYIP=$($DIGCMD -6 +short TXT o-o.myaddr.l.google.com @ns1.google.com | tr -d '"')
fi

if [ "$MYIP" = "$IGNORESTR" ]; then
  MYIP=""
fi

if [ ! -z "$MYIP" ]; then
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
             "OK") echo "$MYNAME: mailinabox API returned OK, cmd succeded but no update.";;
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
  echo "$MYNAME: No ipv6 address found. Check myaddr.google and myip.opendns.com services."
  exit 99
fi


exit 0
