#!/bin/bash
# Written by Onder Vincent Koc
# @url: https://github.com/koconder/dshield_automatic_iptables
# @credits: http://wiki.brokenpoet.org/wiki/Get_DShield_Blocklist
#
# Dshield Automatic Import to iptables
# Import Dshield Blocklist in a basic shell script which will run silently via cron
# and also use a seprate chain file to support other iptables rules without flushing
# i.e. fail2ban and ddosdeflate

# path to iptables
IPTABLES="/sbin/iptables";

# list of known spammers
URL="http://feeds.dshield.org/block.txt";

# save local copy here
FILE="/tmp/dshield_block.text";

# iptables custom chain
CHAIN="dshield";

# check to see if the chain already exists
$IPTABLES -L $CHAIN -n

# check to see if the chain already exists
if [ $? -eq 0 ]; then

    # flush the old rules
    $IPTABLES -F $CHAIN

    echo "Flushed old rules. Applying updated dsheild list...."    

else

    # create a new chain set
    $IPTABLES -N $CHAIN

    # tie chain to input rules so it runs
    $IPTABLES -A INPUT -j $CHAIN

    # don't allow this traffic through
    $IPTABLES -A FORWARD -j $CHAIN

    echo "Chain not detected. Creating new chain and adding dsheild list...."

fi;

# get a copy of the spam list
wget -qc $URL -O $FILE

blocklist=$( cat $FILE | awk '/^[0-9]/' | awk '{print $1"/"$3}'| sort -n)
for IP in $blocklist
do
    # add the ip address log rule to the chain
    $IPTABLES -A $CHAIN -p 0 -s $IP -j LOG --log-prefix "[dsheild BLOCK]" -m limit --limit 3/min --limit-burst 10

    # add the ip address to the chain
    $IPTABLES -A $CHAIN -p 0 -s $IP -j DROP

    echo $IP
done

echo "Done!"

# remove the spam list
unlink $FILE
