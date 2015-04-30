#!/bin/bash

# This adds a log/run file on each runit service directory.
# This file make services stdout/stderr output to svlogd log
# directory located in /var/log/runit/$service.

SERVICES=/etc/service/*

for f in $SERVICES
do
	service=$(basename "$f")
	if [ -d /etc/service/$service ]; then
		echo "Creating log/run for '$service'"
		mkdir -p /etc/service/$service/log
		cat > /etc/service/$service/log/run <<EOF;
#!/bin/bash

mkdir -p /var/log/runit
chmod o-wrx /var/log/runit
mkdir -p /var/log/runit/$service
chmod o-wrx /var/log/runit/$service
exec svlogd -tt /var/log/runit/$service/
EOF
		chmod +x /etc/service/$service/log/run
	fi
done