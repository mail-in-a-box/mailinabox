# Install the 'host', 'sed', and and 'nc' tools. This script is run before
# the rest of the system setup so we may not yet have things installed.
apt_get_quiet install bind9-host sed netcat-openbsd

# Stop if the PRIMARY_HOSTNAME is listed in the Spamhaus Domain Block List.
# The user might have chosen a name that was previously in use by a spammer
# and will not be able to reliably send mail. Do this after any automatic
# choices made above.
if host "$PRIMARY_HOSTNAME.dbl.spamhaus.org" > /dev/null; then
	echo >&2
	echo "The hostname you chose '$PRIMARY_HOSTNAME' is listed in the" >&2
	echo "Spamhaus Domain Block List. See http://www.spamhaus.org/dbl/" >&2
	echo "and http://www.spamhaus.org/query/domain/$PRIMARY_HOSTNAME." >&2
	echo >&2
	echo "You will not be able to send mail using this domain name, so" >&2
	echo "setup cannot continue." >&2
	echo >&2
	exit 1
fi

# Stop if the IPv4 address is listed in the ZEN Spamhouse Block List.
# The user might have ended up on an IP address that was previously in use
# by a spammer, or the user may be deploying on a residential network. We
# will not be able to reliably send mail in these cases.
REVERSED_IPV4=$(echo "$PUBLIC_IP" | sed "s/\([0-9]*\).\([0-9]*\).\([0-9]*\).\([0-9]*\)/\4.\3.\2.\1/")
if host "$REVERSED_IPV4.zen.spamhaus.org" > /dev/null; then
	echo >&2
	echo "The IP address $PUBLIC_IP is listed in the Spamhaus Block List." >&2
	echo "See http://www.spamhaus.org/query/ip/$PUBLIC_IP." >&2
	echo >&2
	echo "You will not be able to send mail using this machine, so setup" >&2
	echo "cannot continue." >&2
	echo >&2
	echo "Associate a different IP address with this machine if possible." >&2
	echo "Many residential network IP addresses are listed, so Mail-in-a-Box" >&2
	echo "typically cannot be used on a residential Internet connection." >&2
	echo >&2
	exit 1
fi

# Stop if we cannot make an outbound connection on port 25. Many residential
# networks block outbound port 25 to prevent their network from sending spam.
# See if we can reach one of Google's MTAs with a 5-second timeout.
if ! nc -z -w5 aspmx.l.google.com 25; then
	echo >&2
	echo "Outbound mail (port 25) seems to be blocked by your network." >&2
	echo >&2
	echo "You will not be able to send mail using this machine, so setup" >&2
	echo "cannot continue." >&2
	echo >&2
	echo "Many residential networks block port 25 to prevent hijacked" >&2
	echo "machines from being able to send spam. I just tried to connect" >&2
	echo "to Google's mail server on port 25 but the connection did not" >&2
	echo "succeed." >&2
	echo >&2
	exit 1
fi
