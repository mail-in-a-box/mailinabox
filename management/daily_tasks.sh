#!/bin/bash
# This script is run daily (at 3am each night).

# Set character encoding flags to ensure that any non-ASCII
# characters don't cause problems. See setup/start.sh and
# the management daemon startup script.
export LANGUAGE=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LC_TYPE=en_US.UTF-8

# Take a backup.
management/backup.py | management/email_administrator.py "Backup Status"

# Provision any new certificates for new domains or domains with expiring certificates.
management/ssl_certificates.py --headless | management/email_administrator.py "Error Provisioning TLS Certificate"

# Run status checks and email the administrator if anything changed.
management/status_checks.py --show-changes | management/email_administrator.py "Status Checks Change Notice"
