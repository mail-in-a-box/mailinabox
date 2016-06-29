# ipset-assassin
ipset-assassin (formerly named blocklist)
This will install a cron to run daily and pull lists from multiple sites to block malicious IP addresses. Adding around ~40,000 or more IP addresses per day, all voluntarily and freely contributed. If setting up Fail2Ban I suggest you help contribute to blocklist.de which is one of the lists used here.
Script is pretty self explanatory it prepares iptables, ipset, and the cron tab. Simply run as root and it will do the work for you. 

2.0 has been rewritten with help from some research to use IPset and far more tables and lists resourced. Please do not run this more than once per day, per server.
This also adds persistence, and removes iptables-persistent from 1.0 as a requirement. In fact you won't need it at all. I average thousands of more malicious IP addresses now ~48,000 as of testing. Maximum ipset can handle is 65535 from what I have read.
Tested on Ubuntu 14.04LTS for my own servers, so please test on your own systems before fully deploying.

Simply run this once, and that's it.
sudo ./install.sh 
alon@ganon.me
https://alonganon.info