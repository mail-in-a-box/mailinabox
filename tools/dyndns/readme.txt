Files:
- dyndns.sh
  Dynamic DNS main script. There should be no need to edit it.
- dyndns.domain
  Fill with the top level domain of your MIAB box.
- dyndns.dynlist
  Fill with subdomains for which the dynamic dns IP should be updated. One per line.
- dyndns.totp
  Fill with TOTP key. Can be found in the MIAB sqlite database
- dyndns.cfg
  Fill with admin user and password
- cronjob.sh
  cronjob file. Edit where needed

How to use:
 - Put dyndns.sh, dyndns.domain, dyndns.dynlist, dyndns.totp and dyndns.cfg in a folder on your target system. E.g. /opt/dyndns
 - Put the cronjob.sh in a cron folder. E.g. /etc/cron.daily
 - Edit the files appropriately