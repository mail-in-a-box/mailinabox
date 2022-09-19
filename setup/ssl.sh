#!/bin/bash
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####

#
# RSA private key, SSL certificate, Diffie-Hellman bits files
# -------------------------------------------

# Create an RSA private key, a SSL certificate signed by a generated
# CA, and some Diffie-Hellman cipher bits, if they have not yet been
# created.
#
# The RSA private key and certificate are used for:
#
#  * DNSSEC DANE TLSA records
#  * IMAP
#  * SMTP (opportunistic TLS for port 25 and submission on ports 465/587)
#  * HTTPS
#  * SLAPD (OpenLDAP server)
#
# The certificate is created with its CN set to the PRIMARY_HOSTNAME. It is
# also used for other domains served over HTTPS until the user installs a
# better certificate for those domains.
#
# The Diffie-Hellman cipher bits are used for SMTP and HTTPS, when a
# Diffie-Hellman cipher is selected during TLS negotiation. Diffie-Hellman
# provides Perfect Forward Secrecy.

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

# Show a status line if we are going to take any action in this file.
if	[ ! -f /usr/bin/openssl ] \
 || [ ! -s $STORAGE_ROOT/ssl/ca_private_key.pem ] \
 || [ ! -f $STORAGE_ROOT/ssl/ca_certificate.pem ] \
 || [ ! -s $STORAGE_ROOT/ssl/ssl_private_key.pem ] \
 || [ ! -f $STORAGE_ROOT/ssl/ssl_certificate.pem ] \
 || [ ! -f $STORAGE_ROOT/ssl/dh2048.pem ]; then
	echo "Creating initial SSL certificate and perfect forward secrecy Diffie-Hellman parameters..."
fi

# Install openssl.

apt_install openssl

# Create a directory to store TLS-related things like "SSL" certificates.

mkdir -p $STORAGE_ROOT/ssl

# Generate new private keys.
#
# Keys are only as good as the entropy available to openssl so that it
# can generate a random key. "OpenSSL’s built-in RSA key generator ....
# is seeded on first use with (on Linux) 32 bytes read from /dev/urandom,
# the process ID, user ID, and the current time in seconds. [During key
# generation OpenSSL] mixes into the entropy pool the current time in seconds,
# the process ID, and the possibly uninitialized contents of a ... buffer
# ... dozens to hundreds of times."
#
# A perfect storm of issues can cause the generated key to be not very random:
#
#	* improperly seeded /dev/urandom, but see system.sh for how we mitigate this
#	* the user ID of this process is always the same (we're root), so that seed is useless
#	* zero'd memory (plausible on embedded systems, cloud VMs?)
#	* a predictable process ID (likely on an embedded/virtualized system)
#	* a system clock reset to a fixed time on boot
#
# Since we properly seed /dev/urandom in system.sh we should be fine, but I leave
# in the rest of the notes in case that ever changes.
if [ ! -s $STORAGE_ROOT/ssl/ca_private_key.pem ]; then
	# Set the umask so the key file is never world-readable.
	(umask 077; hide_output \
		openssl genrsa -aes256 -passout 'pass:SECRET-PASSWORD' \
		-out $STORAGE_ROOT/ssl/ca_private_key.pem 4096)

	# remove the existing ca-certificate, it must be regenerated
	rm -f $STORAGE_ROOT/ssl/ca_certificate.pem
	
	# Remove the ssl_certificate.pem symbolic link to force a
	# regeneration of a self-signed server certificate. Old certs need
	# to be signed by the new ca.
	if [ -L $STORAGE_ROOT/ssl/ssl_certificate.pem ]; then
        # Get the name of the certificate issuer
        issuer="$(openssl x509 -issuer -nocert -in $STORAGE_ROOT/ssl/ssl_certificate.pem)"
        
        # Determine if the ssl cert if self-signed. If unique hashes is 1,
        # the cert is self-signed (pior versions of MiaB used self-signed
        # certs).
        uniq_hashes="$(openssl x509 -subject_hash -issuer_hash -nocert -in $STORAGE_ROOT/ssl/ssl_certificate.pem | uniq | wc -l)"
        
        if [ "$uniq_hashes" == "1" ] || grep "Temporary-Mail-In-A-Box-CA" <<<"$issuer" >/dev/null
        then
		    rm -f $STORAGE_ROOT/ssl/ssl_certificate.pem
	    fi
    fi
fi

if [ ! -s $STORAGE_ROOT/ssl/ssl_private_key.pem ]; then
	# Set the umask so the key file is never world-readable.
	(umask 037; hide_output \
		openssl genrsa -out $STORAGE_ROOT/ssl/ssl_private_key.pem 2048)
	
	# Remove the ssl_certificate.pem symbolic link to force a
	# regeneration of the server certificate. It needs to be
	# signed by the new ca.
	if [ -L $STORAGE_ROOT/ssl/ssl_certificate.pem ]; then
		rm -f $STORAGE_ROOT/ssl/ssl_certificate.pem
	fi
fi

# Give the group 'ssl-cert' read access so slapd can read it
groupadd -fr ssl-cert
chgrp ssl-cert $STORAGE_ROOT/ssl/ssl_private_key.pem
chmod g+r $STORAGE_ROOT/ssl/ssl_private_key.pem

#
# Generate a root CA certificate
#
if [ ! -f $STORAGE_ROOT/ssl/ca_certificate.pem ]; then
	# Generate the self-signed certificate.
	CERT=$STORAGE_ROOT/ssl/ca_certificate.pem
	hide_output \
	openssl req -new -x509 \
	  -days 3650 -sha384 \
	  -key $STORAGE_ROOT/ssl/ca_private_key.pem \
	  -passin 'pass:SECRET-PASSWORD' \
	  -out $CERT \
	  -subj '/CN=Temporary-Mail-In-A-Box-CA'
fi

if [ ! -e /usr/local/share/ca-certificates/mailinabox.crt ]; then
	# add the CA certificate to the system's trusted root ca list
	# this is required for openldap's TLS implementation
    # do this as a separate step in case a CA certificate is manually
    # copied onto the machine for QA/test
	CERT=$STORAGE_ROOT/ssl/ca_certificate.pem
	hide_output \
	  cp $CERT /usr/local/share/ca-certificates/mailinabox.crt
	hide_output \
	  update-ca-certificates
fi


# Generate a signed SSL certificate because things like nginx, dovecot,
# etc. won't even start without some certificate in place, and we need nginx
# so we can offer the user a control panel to install a better certificate.
if [ ! -f $STORAGE_ROOT/ssl/ssl_certificate.pem ]; then
	# # Generate a certificate signing request.
	CSR=/tmp/ssl_cert_sign_req-$$.csr
	hide_output \
	openssl req -new -key $STORAGE_ROOT/ssl/ssl_private_key.pem -out $CSR \
	  -sha256 -subj "/CN=$PRIMARY_HOSTNAME"

	# create a ca database (directory) for openssl
	CADIR=$STORAGE_ROOT/ssl/ca
	mkdir -p $CADIR/newcerts
	touch $CADIR/index.txt $CADIR/index.txt.attr
	[ ! -e $CADIR/serial ] && date +%s > $CADIR/serial

	# Generate the signed certificate.
	CERT=$STORAGE_ROOT/ssl/$PRIMARY_HOSTNAME-cert-$(date --rfc-3339=date | sed s/-//g).pem
	hide_output \
	openssl ca -batch \
		-keyfile $STORAGE_ROOT/ssl/ca_private_key.pem \
		-cert $STORAGE_ROOT/ssl/ca_certificate.pem \
		-passin 'pass:SECRET-PASSWORD' \
		-in $CSR \
		-out $CERT \
		-days 365 \
		-name miab_ca \
		-config - <<< "
[ miab_ca ]
dir		= $CADIR
certs		= \$dir
database	= \$dir/index.txt
unique_subject	= no
new_certs_dir	= \$dir/newcerts	# default place for new certs.
serial		= \$dir/serial		# The current serial number
x509_extensions	= server_cert		# The extensions to add to the cert
name_opt	= ca_default		# Subject Name options
cert_opt	= ca_default		# Certificate field options
policy		= policy_anything
default_md	= default		# use public key default MD

[ policy_anything ]
countryName		= optional
stateOrProvinceName	= optional
localityName		= optional
organizationName	= optional
organizationalUnitName	= optional
commonName		= supplied
emailAddress		= optional

[ server_cert ]
basicConstraints	= CA:FALSE
nsCertType		= server
nsComment		= \"Mail-In-A-Box Generated Certificate\"
subjectKeyIdentifier	= hash
authorityKeyIdentifier	= keyid,issuer
"

	# Delete the certificate signing request because it has no other purpose.
	rm -f $CSR

	# Symlink the certificates into the system certificate path, so system services
	# can find it.
	ln -s $CERT $STORAGE_ROOT/ssl/ssl_certificate.pem
fi

# Generate some Diffie-Hellman cipher bits.
# openssl's default bit length for this is 1024 bits, but we'll create
# 2048 bits of bits per the latest recommendations.
if [ ! -f $STORAGE_ROOT/ssl/dh2048.pem ]; then
	openssl dhparam -out $STORAGE_ROOT/ssl/dh2048.pem 2048
fi
