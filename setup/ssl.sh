#!/bin/bash
#
# SSL Certificate
# ---------------

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
# Generate a new private key.
# Set the umask so the key file is not world-readable.
if [ ! -f $STORAGE_ROOT/ssl/ssl_private_key.pem ]; then
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

# For nginx and postfix, pre-generate some Diffie-Hellman cipher bits which is
# used when a Diffie-Hellman cipher is selected during TLS negotiation. Diffie-Hellman
# provides Perfect Forward Secrecy. openssl's default is 1024 bits, but we'll
# create 2048.
if [ ! -f $STORAGE_ROOT/ssl/dh2048.pem ]; then
	openssl dhparam -out $STORAGE_ROOT/ssl/dh2048.pem 2048
fi
