#!/bin/bash
CONFIG_FILE=/etc/geoiplookup.conf
GEOIPLOOKUP=/usr/local/bin/goiplookup

# Check existence of configuration
if [ -f "$CONFIG_FILE" ]; then
    source $CONFIG_FILE
    
    # Check required variable exists and is non-empty
    if [ -z "$ALLOW_COUNTRIES" ]; then
    	echo "variable ALLOW_COUNTRIES is not set or empty. No countries are blocked."
    	exit 0
    fi
else 
    echo "Configuration $CONFIG_FILE does not exist. No countries are blocked."
    exit 0
fi

# Check existence of binary 
if [ ! -x "$GEOIPLOOKUP" ]; then
    echo "Geoip lookup binary $GEOIPLOOKUP does not exist. No countries are blocked."
    exit 0
fi

if [ $# -ne 1 -a $# -ne 2 ]; then
  echo "Usage:  `basename $0` <ip>" 1>&2
  exit 0 # return true in case of config issue
fi

COUNTRY=`$GEOIPLOOKUP $1 | awk -F ": " '{ print $2 }' | awk -F "," '{ print $1 }' | head -n 1`

[[ $COUNTRY = "IP Address not found" || $ALLOW_COUNTRIES =~ $COUNTRY ]] && RESPONSE="ALLOW" || RESPONSE="DENY"

logger "$RESPONSE geoipblocked connection from $1 ($COUNTRY) $2"

if [ $RESPONSE = "ALLOW" ]
then
  exit 0
else
  exit 1
fi
