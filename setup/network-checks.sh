#!/bin/bash
# Install the 'host', 'sed', and and 'nc' tools. This script is run before
# the rest of the system setup so we may not yet have things installed.
apt_get_quiet install bind9-host sed netcat-openbsd

# Spamhaus answers a lookup with 127.255.255.x when it is declining to answer
# rather than reporting a listing -- a malformed query, a public resolver it
# does not serve, or too many queries. Treating those as a listing tells the
# operator their perfectly good hostname is blacklisted and stops the install.
# See https://www.spamhaus.org/news/article/807/using-our-public-mirrors-check-your-return-codes-now.
# management/status_checks.py already makes this distinction, in
# evaluate_spamhaus_lookup(); this brings setup in line with it.
spamhaus_lookup() {
	host -t A "$1" 2>/dev/null | sed -n 's/.* has address //p' | head -n 1 || true
}

spamhaus_query_refused() {
	case "$1" in
		127.255.255.252) echo "the query was malformed" ;;
		127.255.255.254) echo "this box uses a public DNS resolver, which Spamhaus does not serve" ;;
		127.255.255.255) echo "the Spamhaus query limit has been exceeded" ;;
		*) return 1 ;;
	esac
}

# Stop if the PRIMARY_HOSTNAME is listed in the Spamhaus Domain Block List.
# The user might have chosen a name that was previously in use by a spammer
# and will not be able to reliably send mail. Do this after any automatic
# choices made above.
SPAMHAUS_DBL=$(spamhaus_lookup "$PRIMARY_HOSTNAME.dbl.spamhaus.org")
if SPAMHAUS_WHY=$(spamhaus_query_refused "$SPAMHAUS_DBL"); then
	echo
	echo "WARNING: Could not check whether '$PRIMARY_HOSTNAME' is listed in the"
	echo "Spamhaus Domain Block List, because $SPAMHAUS_WHY."
	echo "Spamhaus answered $SPAMHAUS_DBL. Continuing without this check."
	echo
elif [ -n "$SPAMHAUS_DBL" ]; then
	echo
	echo "The hostname you chose '$PRIMARY_HOSTNAME' is listed in the"
	echo "Spamhaus Domain Block List. See http://www.spamhaus.org/dbl/"
	echo "and http://www.spamhaus.org/query/domain/$PRIMARY_HOSTNAME."
	echo
	echo "You will not be able to send mail using this domain name, so"
	echo "setup cannot continue."
	echo
	exit 1
fi

# Stop if the IPv4 address is listed in the ZEN Spamhouse Block List.
# The user might have ended up on an IP address that was previously in use
# by a spammer, or the user may be deploying on a residential network. We
# will not be able to reliably send mail in these cases.
REVERSED_IPV4=$(echo "$PUBLIC_IP" | sed "s/\([0-9]*\).\([0-9]*\).\([0-9]*\).\([0-9]*\)/\4.\3.\2.\1/")
SPAMHAUS_ZEN=$(spamhaus_lookup "$REVERSED_IPV4.zen.spamhaus.org")
if SPAMHAUS_WHY=$(spamhaus_query_refused "$SPAMHAUS_ZEN"); then
	echo
	echo "WARNING: Could not check whether $PUBLIC_IP is listed in the Spamhaus"
	echo "Block List, because $SPAMHAUS_WHY."
	echo "Spamhaus answered $SPAMHAUS_ZEN. Continuing without this check."
	echo
elif [ -n "$SPAMHAUS_ZEN" ]; then
	echo
	echo "The IP address $PUBLIC_IP is listed in the Spamhaus Block List."
	echo "See http://www.spamhaus.org/query/ip/$PUBLIC_IP."
	echo
	echo "You will not be able to send mail using this machine, so setup"
	echo "cannot continue."
	echo
	echo "Associate a different IP address with this machine if possible."
	echo "Many residential network IP addresses are listed, so Mail-in-a-Box"
	echo "typically cannot be used on a residential Internet connection."
	echo
	exit 1
fi

# Stop if we cannot make an outbound connection on port 25. Many residential
# networks block outbound port 25 to prevent their network from sending spam.
# See if we can reach one of Google's MTAs with a 5-second timeout.
if ! nc -z -w5 aspmx.l.google.com 25; then
	echo
	echo "Outbound mail (port 25) seems to be blocked by your network."
	echo
	echo "You will not be able to send mail using this machine, so setup"
	echo "cannot continue."
	echo
	echo "Many residential networks block port 25 to prevent hijacked"
	echo "machines from being able to send spam. I just tried to connect"
	echo "to Google's mail server on port 25 but the connection did not"
	echo "succeed."
	echo
	exit 1
fi
