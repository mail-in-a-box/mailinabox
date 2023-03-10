#!/bin/bash
source setup/functions.sh

echo Installing geoip packages...

# geo ip filtering of ssh entries, based on https://www.axllent.org/docs/ssh-geoip/#disqus_thread

# Install geo ip lookup tool
gunzip -c tools/goiplookup.gz > /usr/local/bin/goiplookup
chmod +x /usr/local/bin/goiplookup

# check that GeoLite2-Country.mmdb is older then 2 months, to not hit the server too often 
if [[ ! -d /usr/share/GeoIP || ! -f /usr/share/GeoIP/GeoLite2-Country.mmdb || $(find "/usr/share/GeoIP/GeoLite2-Country.mmdb" -mtime +60 -print) ]]; then
  echo updating goiplookup database
  goiplookup db-update
else
  echo skipping goiplookup database update
fi

# Install geoip update cron job
cp -f conf/cron/update_geoipdb /etc/cron.weekly
chmod +x /etc/cron.weekly/update_geoipdb

# Install geo ip filter script
cp -f setup/geoipfilter.sh /usr/local/bin/
chmod +x /usr/local/bin/geoipfilter.sh

# Install only if not yet exists, to keep user config
if [ ! -f /etc/geoiplookup.conf ]; then
    cp -f conf/geoiplookup.conf /etc/
fi

# Add sshd entries for hosts.deny and hosts.allow
if grep -Fxq "sshd: ALL" /etc/hosts.deny
then
    echo hosts.deny already configured
else
    sed -i '/sshd: /d' /etc/hosts.deny
    echo "sshd: ALL" >> /etc/hosts.deny
fi

if grep -Fxq "sshd: ALL: aclexec /usr/local/bin/geoipfilter.sh %a %s" /etc/hosts.allow
then
    echo hosts.allow already configured
else
    # Make sure all sshd lines are removed
    sed -i '/sshd: /d' /etc/hosts.allow
    echo "sshd: ALL: aclexec /usr/local/bin/geoipfilter.sh %a %s" >> /etc/hosts.allow
fi
