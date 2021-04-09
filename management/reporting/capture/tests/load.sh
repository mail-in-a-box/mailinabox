#!/bin/bash

# load a mail.log file into the current test vm's capture.sqlite
#
if [ -z "$1" ]; then
    echo "usage: $0 /path/to/mail.log"
    exit 1
fi

log="$1"
if [ ! -e "$log" ]; then
    echo "Does not exist: $log"
    exit 1
fi

. /etc/mailinabox.conf
if [ $? -ne 0 ]; then
    echo "Could not load /etc/mailinabox.conf !!"
    exit 1
fi


echo "Stopping maibldap-capture daemon"
systemctl stop miabldap-capture || exit 1

echo "Ensuring access to capture.sqlite"
capture_db=$STORAGE_ROOT/reporting/capture.sqlite
sqlite3 "$capture_db" "select value from db_info where key='schema_version'" >/dev/null
[ $? -ne 0 ] && exit 1

echo "Loading $log"
python3 ../capture.py -d -loglevel info -logfile "$log" -stopateof

echo "Starting miabldap-capture daemon"
systemctl start miabldap-capture
