# ipset-assassin
ipset-assassin (formerly named blocklist)
This will install a cron to run daily and pull lists from multiple sites to block malicious IP addresses. Adding around ~40,000 or more IP addresses per day, all voluntarily and freely contributed. If setting up Fail2Ban I suggest you help contribute to blocklist.de which is one of the lists used here.
Script is pretty self explanatory it prepares iptables, ipset, and the cron tab. Simply run as root and it will do the work for you. 

2.0 has been rewritten with help from some research to use IPset and far more tables and lists resourced. Please do not run this more than once per day, per server.
This also adds persistence, and removes iptables-persistent from 1.0 as a requirement. In fact you won't need it at all. I average thousands of more malicious IP addresses now ~48,000 as of testing. Maximum ipset can handle is 65535 from what I have read.
Tested on Ubuntu 14.04LTS for my own servers, so please test on your own systems before fully deploying.

I have also added the capability to block all Chinese and/or Korean IP Addresses in 2.1 as a good number of spam and malicious activity are linked to them. Towards the end after ipset has added thousands of IP addresses, a dialog will appear giving the option to choose if you want to block China, Korea, both, or neither. Simply select the option you desire and it will take care of the rest. The Korean and/or Chinese addresses will only update weekly, as it blocks entire IP blocks off assigned to the country/countries you have chosen. I may add more countries down the line if need be.

2.2 added Dshields top 20 blocks of IP addresses that are malicious, and blocks them daily. It has been merged into the /etc/cron.daily/blacklist created prior. The Dshield script was originally found at https://github.com/koconder/dshield_automatic_iptables

2.3 is a big fix for some bugs I had, so longer requires editing interfaces file. Instead install iptables-persistent, replaces the /etc/init.d/iptables-persistent with another one on GitHub ( https://github.com/jordanrinke/ipsets-persistent ). This does the same for IPtables, but also will save and restore ipset lists as well. The new init.d file has added the ability to save iptables and ipsec configuration from the service command.

2.4 Added the Tor exit node blocking being optional, and rearranged some code and files.

Simply run this once, and that's it.
sudo ./install.sh 
alon@ganon.me
https://alonganon.info
