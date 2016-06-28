#!/bin/sh
# Cron daily for rkhunter by Alon "ChiefGyk" Ganon
# alon@ganon.me
 (
 rkhunter --versioncheck
 rkhunter --update
 rkhunter -c --cronjob 
 ) | mail -s 'rkhunter Daily Check' admin@$DOMAIN