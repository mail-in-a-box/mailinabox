#!/bin/bash
# Checks the status of the SSL certificate and tells the user
# what to do next.

. /etc/mailinabox.conf

if openssl verify $STORAGE_ROOT/ssl/ssl_certificate.pem | grep "self signed" > /dev/null; then
	echo "Your SSL certificate has not yet been signed by a certificate authority (CA)."
	echo
	echo "Before you continue:"
	echo
	echo "* Your email on this Mail-in-a-Box should be working already."
	echo
	echo "Okay, go to https://store.sslmatrix.com/products.php?prod=1&yr=1 and begin the process of ordering a RapidSSL SSL certificate for \$9.95."
	# TODO: Say something about choosing a good password for SSLMatrix?
	echo
	#echo "They'll send you an email with instructions for getting your signed certificate. Remember that since Mail-in-a-Box uses Greylisting, that email may not arrive immediately. (You'll also get another Sales Receipt email, and if you pay by PayPal a third email containing a receipt from PayPal.)"
	echo "After completing your purchase, click My Dashboard, then click your order number. Copy the Configuration PIN to your clipboard, and then next to SSL Status click Configure SSL. Paste the PIN back in and enter the verification code from the image."
	echo
	echo "Copy the following certificate signing request (CSR), including the BEGIN and END lines, to your clipboard:"
	echo
	cat $STORAGE_ROOT/ssl/ssl_cert_sign_req.csr
	echo
	echo "(It is safe to share your CSR. It contains only the public half of your secret SSL information.)"
	echo
	echo "Paste the CSR into the big box. Then click continue. Fill out the form. Pick an email address that you have set up an alias for so you can receive mail to that address. For Server Type, choose Other. Walk through the steps until you have gotten your SSL certificate."
	echo
	echo "Empty the contents of $STORAGE_ROOT/ssl/ssl_certificate.pem. Paste your SSL certificate into the file. Rapid SSL will also tell you to download an intermediate certificate. Download the Bundled CA Version (PEM) and paste it into $STORAGE_ROOT/ssl/ssl_certificate.pem *below* your certificate."
	echo
	echo "Then restart your machine to ensure that system services begin using the SSL certificate."

else
	# Certificate is not self-signed. In order to verify with openssl, we need to split out any
	# intermediary certificates in the chain from our certificate (at the top).

	perl -n0777e '@x = /(-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----)(.*)/sg; print $x[1];' \
		< $STORAGE_ROOT/ssl/ssl_certificate.pem > /tmp/ssl_chain.pem

	openssl verify -verbose -purpose sslserver -policy_check \
		-untrusted /tmp/ssl_chain.pem \
		$STORAGE_ROOT/ssl/ssl_certificate.pem
fi
