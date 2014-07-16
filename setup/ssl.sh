#!/bin/bash
#
# SSL Certificate
#
# Create a self-signed SSL certificate if one has not yet been created.
#
# The certificate is for PRIMARY_HOSTNAME specifically and is used for:
#
#  * IMAP
#  * SMTP submission (port 587) and opportunistic TLS (when on the receiving end)
#  * the DNSSEC DANE TLSA record for SMTP
#  * HTTPS (for PRIMARY_HOSTNAME only)
#
# When other domains besides PRIMARY_HOSTNAME are served over HTTPS,
# we generate a domain-specific self-signed certificate in the management
# daemon (web_update.py) as needed.

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

apt_install openssl

mkdir -p $STORAGE_ROOT/ssl
if [ ! -f $STORAGE_ROOT/ssl/ssl_certificate.pem ]; then
	# Generate a new private key if one doesn't already exist.
	# Set the umask so the key file is not world-readable.
	(umask 077; hide_output \
		openssl genrsa -out $STORAGE_ROOT/ssl/ssl_private_key.pem 2048)
fi
if [ ! -f $STORAGE_ROOT/ssl/ssl_cert_sign_req.csr ]; then
	# Generate a certificate signing request if one doesn't already exist.
	hide_output \
	openssl req -new -key $STORAGE_ROOT/ssl/ssl_private_key.pem -out $STORAGE_ROOT/ssl/ssl_cert_sign_req.csr \
	  -subj "/C=$CSR_COUNTRY/ST=/L=/O=/CN=$PRIMARY_HOSTNAME"
fi
if [ ! -f $STORAGE_ROOT/ssl/ssl_certificate.pem ]; then
	# Generate a SSL certificate by self-signing if a SSL certificate doesn't yet exist.
	hide_output \
	openssl x509 -req -days 365 \
	  -in $STORAGE_ROOT/ssl/ssl_cert_sign_req.csr -signkey $STORAGE_ROOT/ssl/ssl_private_key.pem -out $STORAGE_ROOT/ssl/ssl_certificate.pem
fi

echo
echo "Your SSL certificate's fingerpint is:"
openssl x509 -in $STORAGE_ROOT/ssl/ssl_certificate.pem -noout -fingerprint \
	| sed "s/SHA1 Fingerprint=//"
echo
