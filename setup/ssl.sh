#!/bin/bash
#
# RSA private key, SSL certificate, Diffie-Hellman bits files
# -------------------------------------------

# Create an RSA private key, a self-signed SSL certificate, and some
# Diffie-Hellman cipher bits, if they have not yet been created.
#
# The RSA private key and certificate are used for:
#
#  * DNSSEC DANE TLSA records
#  * IMAP
#  * SMTP (opportunistic TLS for port 25 and submission on port 587)
#  * HTTPS
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

echo "Creating initial SSL certificate and perfect forward secrecy Diffie-Hellman parameters..."
apt_install openssl

mkdir -p $STORAGE_ROOT/ssl

# Generate a new private key.
#
# The key is only as good as the entropy available to openssl so that it
# can generate a random key. "OpenSSL’s built-in RSA key generator ....
# is seeded on first use with (on Linux) 32 bytes read from /dev/urandom,
# the process ID, user ID, and the current time in seconds. [During key
# generation OpenSSL] mixes into the entropy pool the current time in seconds,
# the process ID, and the possibly uninitialized contents of a ... buffer
# ... dozens to hundreds of times."
#
# A perfect storm of issues can cause the generated key to be not very random:
#
#   * improperly seeded /dev/urandom, but see system.sh for how we mitigate this
#   * the user ID of this process is always the same (we're root), so that seed is useless
#   * zero'd memory (plausible on embedded systems, cloud VMs?)
#   * a predictable process ID (likely on an embedded/virtualized system)
#   * a system clock reset to a fixed time on boot
#
# Since we properly seed /dev/urandom in system.sh we should be fine, but I leave
# in the rest of the notes in case that ever changes.
if [ ! -f $STORAGE_ROOT/ssl/ssl_private_key.pem ]; then
	# Set the umask so the key file is never world-readable.
	(umask 077; hide_output \
		openssl genrsa -out $STORAGE_ROOT/ssl/ssl_private_key.pem 2048)
fi

# Generate a certificate signing request.
if [ ! -f $STORAGE_ROOT/ssl/ssl_cert_sign_req.csr ]; then
	hide_output \
	openssl req -new -key $STORAGE_ROOT/ssl/ssl_private_key.pem -out $STORAGE_ROOT/ssl/ssl_cert_sign_req.csr \
	  -sha256 -subj "/C=$CSR_COUNTRY/ST=/L=/O=/CN=$PRIMARY_HOSTNAME"
fi

# Generate a SSL certificate by self-signing.
if [ ! -f $STORAGE_ROOT/ssl/ssl_certificate.pem ]; then
	hide_output \
	openssl x509 -req -days 365 \
	  -in $STORAGE_ROOT/ssl/ssl_cert_sign_req.csr -signkey $STORAGE_ROOT/ssl/ssl_private_key.pem -out $STORAGE_ROOT/ssl/ssl_certificate.pem
fi

# Generate some Diffie-Hellman cipher bits.
# openssl's default bit length for this is 1024 bits, but we'll create
# 2048 bits of bits per the latest recommendations.
if [ ! -f $STORAGE_ROOT/ssl/dh2048.pem ]; then
	openssl dhparam -out $STORAGE_ROOT/ssl/dh2048.pem 2048
fi
