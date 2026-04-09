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
#   Set POSTMARK_TOKEN before running bootstrap, either:
#     a) Export it in /opt/piab/init.sh:  export POSTMARK_TOKEN=your-token-here
#     b) Pass it inline:  POSTMARK_TOKEN=your-token-here bash setup/bootstrap.sh
#
# After setup, the token is stored (root-readable only) in:
#   /etc/postfix/sasl_passwd  (plaintext)
#   /etc/postfix/sasl_passwd.db  (hashed lookup table)

POSTMARK_TOKEN="${POSTMARK_TOKEN:-}"

if [ -z "$POSTMARK_TOKEN" ]; then
	echo "POSTMARK_TOKEN not set; skipping Postmark relay configuration."
	echo "To enable, re-run bootstrap with POSTMARK_TOKEN set."
	exit 0
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

# Apply the new configuration.
systemctl reload postfix

echo "Postmark relay configured. Test with:"
echo "  echo 'test body' | mail -s 'test subject' you@yourdomain.com"
echo "  journalctl -u postfix -f  # watch for smtp.postmarkapp.com 250 OK"
