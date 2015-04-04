SERVICES=/etc/service/*

for f in $SERVICES
do
	service=$(basename "$f")
	if [ "$service" = "syslog-ng" ]; then continue; fi;
	if [ "$service" = "syslog-forwarder" ]; then continue; fi;
	if [ "$service" = "ssh" ]; then continue; fi;
	if [ "$service" = "cron" ]; then continue; fi;
	if ([ -d /etc/service/$service ] && [ ! -f /etc/service/$service/down ]); then
		echo "Creating down file for '$service'"
		touch /etc/service/$service/down
	fi
done