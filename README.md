# blocklist
blocklist-installer
This will install a cron to run daily and pull lists from https://blocklist.de to block malicious IP addresses. Adding around ~20,000 or more IP addresses per day, all voluntarily and freely contributed through people with Fail2Ban accounts. If setting up Fail2Ban I suggest you help contribute to blocklist.de.
Script is pretty self explanatory it prepares IPTables persistence, and the cron tab. Simply run as root and it will do the work for you. 
Tested on Ubuntu 14.04LTS