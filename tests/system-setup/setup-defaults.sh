#!/bin/bash

# Used by setup/start.sh
export PRIMARY_HOSTNAME=${PRIMARY_HOSTNAME:-$(hostname --fqdn || hostname)}
export NONINTERACTIVE=${NONINTERACTIVE:-1}
export SKIP_NETWORK_CHECKS=${SKIP_NETWORK_CHECKS:-1}
export SKIP_SYSTEM_UPDATE=${SKIP_SYSTEM_UPDATE:-1}
export SKIP_CERTBOT=${SKIP_CERTBOT:-1}
export STORAGE_USER="${STORAGE_USER:-user-data}"
export STORAGE_ROOT="${STORAGE_ROOT:-/home/$STORAGE_USER}"
export EMAIL_ADDR="${EMAIL_ADDR:-qa@abc.com}"
export EMAIL_PW="${EMAIL_PW:-Test_1234}"
export PUBLIC_IP="${PUBLIC_IP:-$(source ${MIAB_DIR:-.}/setup/functions.sh; get_default_privateip 4)}"
export LOCAL_MODS_DIR="${LOCAL_MODS_DIR:-local}"
export DOWNLOAD_CACHE_DIR="${DOWNLOAD_CACHE_DIR:-$(pwd)/downloads}"
export DOWNLOAD_NEXTCLOUD_FROM_GITHUB="${DOWNLOAD_NEXTCLOUD_FROM_GITHUB:-false}"

# Used by ehdd/start-encrypted.sh
export EHDD_KEYFILE="${EHDD_KEYFILE:-}"
export EHDD_GB="${EHDD_GB:-2}"


# Placing this var in STORAGE_ROOT/ldap/miab_ldap.conf before running
# setup/start.sh will avoid a random password from being used for the
# Nextcloud LDAP service account
export LDAP_NEXTCLOUD_PASSWORD=${LDAP_NEXTCLOUD_PASSWORD:-Test_LDAP_1234}

# Used by setup/mods.available/remote-nextcloud.sh. These define to
# MiaB-LDAP the remote Nextcloud that serves calendar and contacts
export NC_PROTO=${NC_PROTO:-http}
export NC_HOST=${NC_HOST:-127.0.0.1}
export NC_PORT=${NC_PORT:-8000}
export NC_PREFIX=${NC_PREFIX:-/}

# For setup scripts that may be installing a remote Nextcloud
export NC_ADMIN_USER="${NC_ADMIN_USER:-admin}"
export NC_ADMIN_PASSWORD="${NC_ADMIN_PASSWORD:-Test_1234}"

# For setup scripts that install upstream versions
export MIAB_UPSTREAM_GIT="${MIAB_UPSTREAM_GIT:-https://github.com/mail-in-a-box/mailinabox.git}"
export UPSTREAM_TAG="${UPSTREAM_TAG:-}"

# For setup scripts that install miabldap releases
export MIABLDAP_GIT="${MIABLDAP_GIT:-https://github.com/downtownallday/mailinabox-ldap.git}"
export MIABLDAP_RELEASE_TAG="${MIABLDAP_RELEASE_TAG:-v0.54}"
