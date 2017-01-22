#!/bin/bash
#
# This script will save debug info to either a gist or /tmp/

# Are we running as root?
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root. Please re-run like this:"
  echo
  echo "sudo $0"
  echo
  exit
fi

echo "This script produces a diagnostic log to help the maintainers"
echo "figure out why your Mail-in-a-Box installation isn't working the"
echo "way you expected it to."

echo
echo "This log will contain sensitive information about your installation"
echo "including, but not limited to:"
echo "email addresses"
echo "domain names"
echo "IP addresses"
echo "server security configuration"
echo "etc."
echo
echo "====================================================================="
echo "Please do not post this file to the internet if you are not comfortable"
echo "exposing this information publicly to the world forever."
echo "====================================================================="
echo
echo "Once the log has been collected, you will be given the option to post"
echo "the log to https://gist.github.com/ so that others can help you diagnose"
echo "the issues with your Mail-in-a-Box installation"
echo
echo "You are solely responsible for the data you choose to publish"

source /etc/mailinabox.conf # load global vars
TMP_FILE=/tmp/MIAB_debug_$(date -d "today" +"%Y%m%d%H%M%S").log

touch $TMP_FILE;

# MIAB status checks
/root/mailinabox/management/status_checks.py >> $TMP_FILE;
echo >> $TMP_FILE; # newline after status_checks

# all of the commands we want to run.
declare -a commands=("uptime"
                     "lsb_release -a"
                     "free -m"
                     "df -h"
                     "ps auxf"
                     "pip3 list"
                     "dpkg --list"
                     "ufw status verbose"
                     "ifconfig"
                     "lsof -i"
                     "cat /etc/hosts"
                     "cat /etc/resolv.conf"
                     "cat /var/log/syslog"
                     "cat /var/log/mail.log"
                     "cat /var/log/boot.log"
                     "cat /var/log/roundcubemail/errors"
                     )

function name_and_delineator () {
  CMD_LENGTH=${#1}
  DELINEATOR="";
  for (( c=1; c<=$CMD_LENGTH; c++ ))
  do
     DELINEATOR+="=";
  done
  echo $1 >> $TMP_FILE
  echo $DELINEATOR >> $TMP_FILE;
}

# iterate through each command, announce it, execute it and log it.
for i in "${commands[@]}"
do
  echo "executing: $i and saving output to $TMP_FILE"
  name_and_delineator "$i" # pretty printing
  eval `echo $i` >> $TMP_FILE # execute string as a command, including spaces
  echo >> $TMP_FILE; # newline
done

function post_gist () {
  echo "Posting the debug log to https://gist.github.com at this url:"
  echo $(gist-paste -p -s `echo $TMP_FILE`)
  echo "Please provide this url to help diagnose your issue."
}

# double check that the user wants to post to github.
echo "Do You want to post your debug log on https://gist.github.com publicly?"
echo "Please type 'YES' below, anything else will cancel."
echo -n "Type YES to publish:"
read answer
if echo "$answer" | grep -q "^YES" ;then
  if [ ! -f /root/.gist ]; then
    echo "You will need to log into Github first."
    echo "You can skip this step by pressing <ctrl-c>, but you will not"
    echo "be able to delete the debug log if you do not log in."
    gist-paste --login
    # ask again, just to be sure.
    echo "Are you sure you want to post your debug log on https://gist.github.com publicly?"
    echo "Please type 'YES' below, anything else will cancel."
    echo -n "Type YES to publish:"
    read answer
    if echo "$answer" | grep -q "^YES" ;then
      post_gist
    else
      # logged in to github, but said no on the second request
      echo "Your debug log file is here: $TMP_FILE"
    fi
  else
    post_gist
  fi
else # said no to initial request to post to gist.github.com
  echo "Your debug log file is here: $TMP_FILE"
fi
