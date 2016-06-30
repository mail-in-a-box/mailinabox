# ipset-assassin

This will install a cron to run daily and pull lists from multiple sites to block malicious IP addresses. Adding around ~40,000 or more IP addresses per day, all voluntarily and freely contributed. If setting up Fail2Ban I suggest you help contribute to blocklist.de which is one of the lists used here. 
Script is pretty self explanatory it prepares iptables, ipset, and the cron tab. Simply run as root and it will do the work for you. 

2.0 has been rewritten with help from some research to use IPset and far more tables and lists resourced. Please do not run this more than once per day, per server.
This also adds persistence, and removes iptables-persistent from 1.0 as a requirement. In fact you won't need it at all. I average thousands of more malicious IP addresses now ~48,000 as of testing. Maximum ipset can handle is 65535 from what I have read.
Tested on Ubuntu 14.04LTS for my own servers, so please test on your own systems before fully deploying.

I have also added the capability to block all Chinese and/or Korean IP Addresses in 2.1 as a good number of spam and malicious activity are linked to them. Towards the end after ipset has added thousands of IP addresses, a dialog will appear giving the option to choose if you want to block China, Korea, both, or neither. Simply select the option you desire and it will take care of the rest. The Korean and/or Chinese addresses will only update weekly, as it blocks entire IP blocks off assigned to the country/countries you have chosen. I may add more countries down the line if need be.

2.2 added Dshields top 20 blocks of IP addresses that are malicious, and blocks them daily. 

2.3 is a big fix for some bugs I had, so longer requires editing interfaces file. Instead install iptables-persistent, replaces the /etc/init.d/iptables-persistent with another one on GitHub. Read below where it says ipsets-persistent

2.4 Added the Tor exit node blocking being optional, and rearranged some code and files.
2.41 Added Malc0de blocklist

The lists used:
Project Honey Pot:		http://www.projecthoneypot.org/list_of_ips.php?t=d&rss=1
TOR Exit Nodes:			http://check.torproject.org/cgi-bin/TorBulkExitList.py?ip=1.1.1.1
BruteForceBlocker: 		http://danger.rulez.sk/projects/bruteforceblocker/blist.php
Spamhaus:				http://www.spamhaus.org/drop/drop.lasso
C.I. Army:				http://cinsscore.com/list/ci-badguys.txt
OpenBL.org:				http://www.openbl.org/lists/base.txt
Autoshun:				http://www.autoshun.org/files/shunlist.csv
Blocklist.de:			http://lists.blocklist.de/lists/all.txt
Dshield:				http://feeds.dshield.org/block.txt
Malware Domain List:	https://www.malwaredomainlist.com/hostslist/ip.txt
ZeusTracker:			https://zeustracker.abuse.ch/blocklist.php?download=ipblocklist
malc0de IP blacklist:	http://malc0de.com/bl/IP_Blacklist.txt"

Simply run this once, and that's it.
sudo ./install.sh 
alon@ganon.me
https://alonganon.info

======
#ipsets-persistent
https://github.com/jordanrinke/ipsets-persistent


init.d script for iptables-persistent on Debian/Ubuntu that also saves/loads ipsets


I added checking for and saving ipsets. sets are saved in the same place as the other rules in a file named rules.ipset. Rules are only saved if they are defined, same with flushing and loading. Instead of checking to see if ipset is installed on the load, I just check for the rules.ipset file, since if that doesn't exist loading does't make sense. There might be better ways to do it, feel free to submit a pull etc. this is just the way I made it work for me.

=======
#dshield_automatic_iptables

https://github.com/koconder/dshield_automatic_iptables


Auto Import dshield blocklist and import to iptables as a chain. It has been merged into the /etc/cron.daily/blacklist created prior in conf/blacklist.

