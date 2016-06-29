# blocklist
blocklist-installer
This will install a cron to run daily and pull lists from https://blocklist.de to block malicious IP addresses. Adding around ~40,000 or more IP addresses per day, all voluntarily and freely contributed through people with Fail2Ban accounts. If setting up Fail2Ban I suggest you help contribute to blocklist.de.
Script is pretty self explanatory it prepares IPTables persistence, and the cron tab. Simply run as root and it will do the work for you. 

2.0 has been rewritten with help from some research to use IPset and far more tables and lists resourced. Please do not run this more than once per day, per server.
This also adds persistence, and removes iptables-persistent from 1.0 as a requirement. In fact you won't need it at all. I average thousands of more malicious IP addresses now ~48,000 as of testing. Maximum ipset can handle is 65535 from what I have read.
Tested on Ubuntu 14.04LTS
alon@ganon.me
https://alonganon.info