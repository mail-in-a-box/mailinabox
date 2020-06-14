#!/bin/bash

# setup MiaB-LDAP with a remote Nextcloud running on the same
# host under Docker exposed as localhost:8000
#
# to use:
#   on a fresh Ubuntu:
#      1. checkout or copy the MiaB-LDAP code to ~/mailinabox
#      2. cd ~/mailinabox
#      3. sudo tests/system-setup/remote-nextcloud-docker.sh
#
# when complete you should have a working MiaB-LDAP and Nextcloud
#
# You can access MiaB-LDAP using your browser to the Ubuntu system in
# the normal way, (eg: https://<ubuntu-box>/admin).
#
# Nextcloud is running under Docker on the ubuntu box, so to access it
# you'll first need to ssh into the ubuntu box with port-forrwarding
# enabled.
#
# eg: ssh -L 8000:localhost:8000 user@<ubuntu-box>
#
# Then, in your browser visit http://localhost:8000/.
#
# See setup-defaults.sh for usernames and passwords.
#


usage() {
    echo "Usage: $(basename "$0")"
    echo "Install MiaB-LDAP and a remote Nextcloud running under docker"
    echo "Nextcloud is exposed as http://localhost:8000"
    exit 1
}

# ensure working directory
if [ ! -d "tests/system-setup" ]; then
    echo "This script must be run from the MiaB root directory"
    exit 1
fi

# load helper scripts
. "tests/lib/all.sh" "tests/lib" || die "Could not load lib scripts"
. "tests/system-setup/setup-defaults.sh" || die "Could not load setup-defaults"
. "tests/system-setup/setup-funcs.sh" || die "Could not load setup-funcs"

# ensure running as root
if [ "$EUID" != "0" ]; then
    die "This script must be run as root (sudo)"
fi



before_miab_install() {
    H1 "BEFORE MIAB-LDAP INSTALL"
    system_init
    miab_testing_init || die "Initialization failed"
    
    # enable the remote Nextcloud setup mod, which tells MiaB-LDAP to use
    # the remote Nextcloud for calendar and contacts instead of the
    # MiaB-installed one
    H2 "Enable local mod remote-nextcloud"
    enable_miab_mod "remote-nextcloud" \
        || die "Could not enable remote-nextcloud mod"
    
    # install Docker
    H2 "Install Docker"
    install_docker || die "Could not install Docker! ($?)"
}


miab_install() {
    H1 "MIAB-LDAP INSTALL"
    if ! setup/start.sh; then
        H1 "OUTPUT OF SELECT FILES"
        dump_file "/var/log/syslog" 100
        dump_conf_files "$TRAVIS"
        H2; H2 "End"; H2
        die "setup/start.sh failed!"
    fi
    H1 "OUTPUT OF SELECT FILES"
    dump_conf_files "$TRAVIS"
    H2; H2 "End"; H2
}


after_miab_install() {
    H1 "AFTER MIAB-LDAP INSTALL"
    
    . /etc/mailinabox.conf || die "Could not load /etc/mailinabox.conf"
    
    # run Nextcloud docker image
    H2 "Start Nextcloud docker container"
    local container_started="true"
    if [ -z "$(docker ps -f NAME=NC -q)" ]; then
        docker run -d --name NC -p 8000:80 \
               --env SQLITE_DATABASE=nextclouddb.sqlite \
               --env NEXTCLOUD_ADMIN_USER="$NC_ADMIN_USER" \
               --env NEXTCLOUD_ADMIN_PASSWORD="$NC_ADMIN_PASSWORD" \
               --env NEXTCLOUD_TRUSTED_DOMAINS="127.0.0.1 ::1" \
               --env NEXTCLOUD_UPDATE=1 \
               --env SMTP_HOST="$PRIMARY_HOSTNAME" \
               --env SMTP_SECURE="tls" \
               --env SMTP_PORT=587 \
               --env SMTP_AUTHTYPE="LOGIN" \
               --env SMTP_NAME="$EMAIL_ADDR" \
               --env SMTP_PASSWORD="$EMAIL_PW" \
               --env SMTP_FROM_ADDRESS="$(email_localpart "$EMAIL_ADDR")" \
               --env MAIL_DOMAIN="$(email_domainpart "$EMAIL_ADDR")" \
               nextcloud:latest \
            || die "Docker run failed!"
    else
        echo "Container already running"
        container_started="false"
    fi

    H2 "docker: Update /etc/hosts so it can find MiaB-LDAP by name"
    echo "$PRIVATE_IP $PRIMARY_HOSTNAME" | \
        docker exec -i NC bash -c 'cat >>/etc/hosts' \
        || die "docker: could not update /etc/hosts"
    
    # apt-get update
    H2 "docker: apt-get update"
    docker exec NC apt-get update || die "docker: apt-get update failed"

    # allow LDAP access from docker image
    H2 "Allow ldaps through firewall so Nextcloud can perform LDAP searches"
    ufw allow ldaps || die "Unable to modify firewall to permit ldaps"

    # add MiaB-LDAP's ca_certificate.pem to docker's trusted cert list
    H2 "docker: update trusted CA list"
    docker cp \
           $STORAGE_ROOT/ssl/ca_certificate.pem \
           NC:/usr/local/share/ca-certificates/mailinabox.crt \
        || die "docker: copy ca_certificate.pem failed"
    docker exec NC update-ca-certificates \
        || die "docker: update-ca-certificates failed"

    # wait for Nextcloud installation to complete
    H2 "Wait for Nextcloud installation to complete"
    wait_for_docker_nextcloud NC installed || die "Giving up"
    
    # install and enable Nextcloud apps
    H2 "docker: install Nextcloud calendar app"
    if ! docker exec -u www-data NC ./occ app:install calendar
    then
        $container_started || die "docker: installing calendar app failed"
    fi
    
    H2 "docker: install Nextcloud contacts app"
    if ! docker exec -u www-data NC ./occ app:install contacts
    then
        $container_started || die "docker: installing contacts app failed"
    fi
    
    H2 "docker: enable user_ldap"
    docker exec -u www-data NC ./occ app:enable user_ldap \
        || die "docker: enabling user_ldap failed ($?)"

    # integrate Nextcloud with MiaB-LDAP
    H2 "docker: integrate Nextcloud with MiaB-LDAP"
    docker cp setup/mods.available/remote-nextcloud-use-miab.sh NC:/tmp \
        || die "docker: cp remote-nextcloud-use-miab.sh failed"
    docker exec NC /tmp/remote-nextcloud-use-miab.sh \
           . \
           "$NC_ADMIN_USER" \
           "$NC_ADMIN_PASSWORD" \
           "$PRIMARY_HOSTNAME" \
           "$LDAP_NEXTCLOUD_PASSWORD" \
        || die "docker: error running remote-nextcloud-use-miab.sh"
}


#
# Main
#
case "${1:-all}" in
    before-install )
        before_miab_install
        ;;
    install )
        miab_install
        ;;
    after-install )
        after_miab_install
        ;;
    all )
        before_miab_install
        miab_install
        after_miab_install
        ;;
    * )
        usage
        ;;
esac

