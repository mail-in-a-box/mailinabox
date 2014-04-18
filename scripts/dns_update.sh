# DNS: Creates DNS zone files
#############################

# Create nsd.conf and zone files, and updates the OpenDKIM signing tables.

# We set the administrative email address for every domain to domain_contact@[domain.com].
# You should probably create an alias to your email address.

# This script is safe to run on its own.

source /etc/mailinabox.conf # load global vars

# Ensure a zone file exists for every domain name in use by a mail user.
for mail_user in `tools/mail.py user`; do
	domain=`echo $mail_user | sed s/.*@//`
	if [ ! -f $STORAGE_ROOT/dns/$domain.txt ]; then
		echo "" > $STORAGE_ROOT/dns/$domain.txt;
	fi
done

# Create the top of nsd.conf.

cat > /etc/nsd/nsd.conf << EOF;
server:
  hide-version: yes

  # identify the server (CH TXT ID.SERVER entry).
  identity: ""

  # The directory for zonefile: files.
  zonesdir: "/etc/nsd/zones"
  
# ZONES
EOF

# For every zone file in our dns directory, build a proper zone
# file and mention it in nsd.conf. And add information to the
# OpenDKIM signing tables.

mkdir -p /etc/nsd/zones;

truncate --size 0 /etc/opendkim/KeyTable
truncate --size 0 /etc/opendkim/SigningTable

for fn in $STORAGE_ROOT/dns/*.txt; do
	# $fn is the zone configuration file, which is just a placeholder now.
	#     For every file like mydomain.com.txt we'll create zone information
	#     for that domain. We don't actually read the file.
	# $fn2 is the file without the directory.
	# $zone is the domain name (just mydomain.com).
	fn2=`basename $fn`
	zone=`echo $fn2 | sed "s/.txt\$//"`
	
	# If the zone file exists, get the existing zone serial number so we can increment it.
	# TODO: This needs to be done better so that the existing serial number is persisted in the storage area.
	serial=`date +"%Y%m%d00"`
	if [ -f /etc/nsd/zones/$fn2 ]; then
		existing_serial=`grep "serial number" /etc/nsd/zones/$fn2 | sed "s/; serial number//"`
		if [ ! -z "$existing_serial" ]; then
			serial=`echo $existing_serial + 1 | bc`
		fi
	fi

	# Create the zone file.
	cat > /etc/nsd/zones/$fn2 << EOF;
\$ORIGIN $zone.    ; default zone domain
\$TTL 86400           ; default time to live

@ IN SOA ns1.$PUBLIC_HOSTNAME. hostmaster.$PUBLIC_HOSTNAME. (
           $serial     ; serial number
           28800       ; Refresh
           7200        ; Retry
           864000      ; Expire
           86400       ; Min TTL
           )

           NS          ns1.$PUBLIC_HOSTNAME.
           NS          ns2.$PUBLIC_HOSTNAME.
           IN     A    $PUBLIC_IP
           MX     10   $PUBLIC_HOSTNAME.

           300    TXT  "v=spf1 mx -all"

www        IN     A    $PUBLIC_IP
EOF

	# In PUBLIC_HOSTNAME, also define ns1 and ns2.
	if [ "$zone" = $PUBLIC_HOSTNAME ]; then
		cat >> /etc/nsd/zones/$fn2 << EOF;
ns1        IN     A    $PUBLIC_IP
ns2        IN     A    $PUBLIC_IP
EOF
	fi

	# If OpenDKIM is set up, append the suggested TXT record to the zone.
	if [ -f "$STORAGE_ROOT/mail/dkim/mail.txt" ]; then
		cat "$STORAGE_ROOT/mail/dkim/mail.txt" >> /etc/nsd/zones/$fn2;
	fi
	
	# Add this zone file to the main nsd configuration file.
	cat >> /etc/nsd/nsd.conf << EOF;
zone:
	name: $zone
	zonefile: $fn2
EOF

	# Append a record to OpenDKIM's KeyTable and SigningTable. The SigningTable maps
	# email addresses to signing information. The KeyTable maps specify the hostname,
	# the selector, and the path to the private key.
	#
	# Just in case we don't actually host the DNS for all domains of our mail users,
	# we assume that DKIM is at least configured in the DNS of $PUBLIC_HOSTNAME and
	# we use that host for all DKIM signatures.
	#
	# In SigningTable, we map every email address to a key record called $zone.
	# Then we specify for the key record named $zone its domain, selector, and key.
	echo "$zone $PUBLIC_HOSTNAME:mail:$STORAGE_ROOT/mail/dkim/mail.private" >> /etc/opendkim/KeyTable
	echo "*@$zone $zone" >> /etc/opendkim/SigningTable

done

# Kick nsd.
service nsd rebuild
service nsd restart # ensure it is running

# Kick opendkim.
service opendkim restart

