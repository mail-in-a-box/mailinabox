# Create nsd.conf and zone files, and updates the OpenDKIM signing tables.

source /etc/mailinabox.conf
PUBLIC_IP=`cat $STORAGE_ROOT/dns/our_ip`

# Create the top of nsd.conf.

cat > /etc/nsd3/nsd.conf << EOF;
server:
  hide-version: yes

  # identify the server (CH TXT ID.SERVER entry).
  identity: ""

  # The directory for zonefile: files.
  zonesdir: "/etc/nsd3/zones"
  
# ZONES
EOF

# For every zone file in our dns directory, build a proper zone
# file and mention it in nsd.conf. And add information to the
# OpenDKIM signing tables.

mkdir -p /etc/nsd3/zones;

truncate --size 0 /etc/opendkim/KeyTable
truncate --size 0 /etc/opendkim/SigningTable

for fn in $STORAGE_ROOT/dns/*.txt; do
	fn2=`basename $fn`
	zone=`echo $fn2 | sed "s/.txt\$//"`
	
	# If the zone file exists, increment the serial number.
	# TODO: This needs to be done better so that the existing serial number is
	# persisted in the storage area.
	serial=`date +"%Y%m%d00"`
	if [ -f /etc/nsd3/zones/$fn2 ]; then
		existing_serial=`grep "serial number" /etc/nsd3/zones/$fn2 | sed "s/; serial number//"`
		if [ ! -z "$existing_serial" ]; then
			serial=`echo $existing_serial + 1 | bc`
		fi
	fi

	cat > /etc/nsd3/zones/$fn2 << EOF;
\$ORIGIN $zone.    ; default zone domain
\$TTL 86400           ; default time to live

@ IN SOA ns1.$zone. domain_contact.$zone. (
           $serial     ; serial number
           28800       ; Refresh
           7200        ; Retry
           864000      ; Expire
           86400       ; Min TTL
           )

           NS          ns1.$zone.
           NS          ns2.$zone.
           IN     A    $PUBLIC_IP
           MX     10   mail.$zone.
           
           300    TXT  "v=spf1 mx -all"

ns1        IN     A    $PUBLIC_IP
ns2        IN     A    $PUBLIC_IP
mail       IN     A    $PUBLIC_IP
www        IN     A    $PUBLIC_IP
EOF

	# If OpenDKIM is set up, append that information to the zone.
	if [ -f "$STORAGE_ROOT/mail/dkim/mail.txt" ]; then
		cat "$STORAGE_ROOT/mail/dkim/mail.txt" >> /etc/nsd3/zones/$fn2;
	fi
	
	cat >> /etc/nsd3/nsd.conf << EOF;
zone:
	name: $zone
	zonefile: $fn2
EOF

	# OpenDKIM
	
	echo "$zone $zone:mail:$STORAGE_ROOT/mail/dkim/mail.private" >> /etc/opendkim/KeyTable
	echo "*@$zone $zone" >> /etc/opendkim/SigningTable

done

# Kick nsd.
service nsd3 rebuild
service nsd3 restart # ensure it is running

# Kick opendkim.
service opendkim restart

