#!/bin/bash
set -euo pipefail

# Download select set of malware blocklists from The Firebog's "The Big Blocklist
# Collection" [0] and block access to them with Unbound by returning NXDOMAIN.
#
# Usage:
# # create the blocklist
# create_dns_blocklist.sh > ~/blocklist.conf
# sudo mv ~/blocklist.conf /etc/unbound/lists.d
#
# # check list contains valid syntax. If not valid, remove blocklist.conf,
# # otherwise unbound will not work
# sudo unbound-checkconf
# > unbound-checkconf: no errors in /etc/unbound/unbound.con
#
# # reload unbound configuration
# sudo unbound-control reload
#
#
#   [0]: https://firebog.net
(
  # Malicious Lists
  curl -sSf "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/Alternate%20versions%20Anti-Malware%20List/AntiMalwareHosts.txt" ;
  curl -sSf "https://osint.digitalside.it/Threat-Intel/lists/latestdomains.txt" ;
  curl -sSf "https://s3.amazonaws.com/lists.disconnect.me/simple_malvertising.txt" ;
  curl -sSf "https://v.firebog.net/hosts/Prigent-Crypto.txt" ;
  curl -sSf "https://bitbucket.org/ethanr/dns-blacklists/raw/8575c9f96e5b4a1308f2f12394abd86d0927a4a0/bad_lists/Mandiant_APT1_Report_Appendix_D.txt" ;
  curl -sSf "https://phishing.army/download/phishing_army_blocklist_extended.txt" ;
  curl -sSf "https://gitlab.com/quidsup/notrack-blocklists/raw/master/notrack-malware.txt" ;
  curl -sSf "https://raw.githubusercontent.com/Spam404/lists/master/main-blacklist.txt" ;
  curl -sSf "https://raw.githubusercontent.com/FadeMind/hosts.extras/master/add.Risk/hosts" ;
  curl -sSf "https://urlhaus.abuse.ch/downloads/hostfile/" ;
#  curl -sSf "https://v.firebog.net/hosts/Prigent-Malware.txt" ;
#  curl -sSf "https://v.firebog.net/hosts/Shalla-mal.txt" ;

) |
  cat |                # Combine all lists into one
  grep -v '#' |        # Remove comments lines
  grep -v '::' |       # Remove universal ipv6 address
  tr -d '\r' |         # Normalize line endings by removing Windows carriage returns
  sed -e 's/0\.0\.0\.0\s\{0,\}//g' |     # Remove ip address from start of line
  sed -e 's/127\.0\.0\.1\s\{0,\}//g' |
  sed -e '/^$/d' |                       # Remove empty line
  sort -u |                              # Sort and remove duplicates
  awk '{print "local-zone: " ""$1"" " always_nxdomain"}' # Convert to Unbound configuration
  