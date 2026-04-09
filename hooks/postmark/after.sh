#!/bin/bash
#
# Postmark Outbound Relay Hook
# ----------------------------
# Install this file as /opt/piab/after.sh to route all outbound mail
# through Postmark's SMTP relay instead of delivering directly.
#
# Prerequisites:
#   - A Postmark account with a verified Sender Signature or Domain
#   - A Postmark Server API Token
#
# Usage:
#   Set POSTMARK_TOKEN and POSTMARK_SENDER before running bootstrap, either:
#     a) Export them in /opt/piab/init.sh:
#          export POSTMARK_TOKEN=your-token-here
#          export POSTMARK_SENDER=you@yourdomain.com
#     b) Pass them inline:
#          POSTMARK_TOKEN=your-token POSTMARK_SENDER=you@yourdomain.com bash setup/bootstrap.sh
#
# After setup, the token is stored (root-readable only) in:
#   /etc/postfix/sasl_passwd  (plaintext)
#   /etc/postfix/sasl_passwd.db  (hashed lookup table)

POSTMARK_TOKEN="${POSTMARK_TOKEN:-}"
POSTMARK_SENDER="${POSTMARK_SENDER:-}"

if [ -z "$POSTMARK_TOKEN" ]; then
	echo "POSTMARK_TOKEN not set; skipping Postmark relay configuration."
	echo "To enable, re-run bootstrap with POSTMARK_TOKEN set."
	return 0 2>/dev/null || exit 0
fi

if [ -z "$POSTMARK_SENDER" ]; then
	echo "POSTMARK_SENDER not set; skipping Postmark relay configuration."
	echo "Set this to the verified Sender Signature address in your Postmark account."
	return 0 2>/dev/null || exit 0
fi

echo "Configuring Postfix to relay outbound mail through Postmark..."

# Configure the relay host and SASL authentication.
#
# smtp_tls_security_level is changed from 'dane' (the default set by
# mail-postfix.sh) to 'encrypt' because we are routing all outbound mail
# through a single relay host. Postmark supports TLS on port 587, so
# 'encrypt' ensures the relay connection is always encrypted without
# requiring DANE/TLSA records on smtp.postmarkapp.com.
tools/editconf.py /etc/postfix/main.cf \
	relayhost="[smtp.postmarkapp.com]:587" \
	smtp_sasl_auth_enable=yes \
	smtp_sasl_password_maps="hash:/etc/postfix/sasl_passwd" \
	smtp_sasl_security_options=noanonymous \
	smtp_tls_security_level=encrypt

# Write the SASL credentials file.
# Postmark uses the Server API Token as both username and password.
printf '[smtp.postmarkapp.com]:587\t%s:%s\n' "$POSTMARK_TOKEN" "$POSTMARK_TOKEN" \
	> /etc/postfix/sasl_passwd

# Hash the credentials file for Postfix lookup and restrict permissions.
postmap hash:/etc/postfix/sasl_passwd
chmod 600 /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db

# Install libsasl2-modules if not present (required for SASL PLAIN/LOGIN auth).
if ! dpkg -s libsasl2-modules > /dev/null 2>&1; then
	echo "Installing libsasl2-modules for SASL authentication..."
	apt-get -q -q install -y libsasl2-modules < /dev/null
fi

# Rewrite the envelope sender on outbound relay to match the verified
# Postmark Sender Signature. Uses smtp_sender_canonical_maps so only the
# sender address is rewritten, and only at the smtp client (relay) stage —
# recipient addresses and local delivery are unaffected.
printf '/^.*@.*$/ %s\n' "$POSTMARK_SENDER" \
	> /etc/postfix/smtp_sender_canonical
tools/editconf.py /etc/postfix/main.cf \
	smtp_sender_canonical_maps="regexp:/etc/postfix/smtp_sender_canonical"
# Remove smtp_generic_maps if previously set, to avoid double-rewriting.
tools/editconf.py /etc/postfix/main.cf -e smtp_generic_maps=

# Apply the new configuration.
systemctl reload postfix

echo "Postmark relay configured with sender rewrite to $POSTMARK_SENDER."
echo "Test with:"
echo "  echo 'test body' | mail -s 'test subject' you@yourdomain.com"
echo "  tail -f /var/log/mail.log  # watch for smtp.postmarkapp.com 250 OK"
