#!/bin/bash
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####


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



init() {
    H1 "INIT"
    init_test_system
    init_miab_testing "$@" || die "Initialization failed"
}


install_nextcloud_docker() {
    H1 "INSTALL NEXTCLOUD ON DOCKER"

    # install Docker
    H2 "Install Docker"
    install_docker || die "Could not install Docker! ($?)"

    # run Nextcloud docker image
    H2 "Start Nextcloud docker container"
    local container_started="true"
    if [ -z "$(docker ps -f NAME=NC -q)" ]; then
        docker run -d --name NC -p 8000:80 \
               --add-host "$PRIMARY_HOSTNAME:$PRIVATE_IP" \
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

    # apt-get update
    H2 "docker: apt-get update"
    docker exec NC apt-get update || die "docker: apt-get update failed"

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

    # ldap queries from the container use the container's ip address,
    # not the exposed docker port for nextcloud. the variable
    # NC_HOST_SRC_IP is used by the remote-nextcloud mod to configure
    # the firewall allowing ldap queries to reach slapd from the
    # container
    export NC_HOST_SRC_IP=$(get_container_ip)
    [ $? -ne 0 ] && die "Unable to get docker container IP address"
}

get_container_ip() {
    local id
    id=$(docker ps -aqf "name=NC")
    [ $? -ne 0 ] && return 1
    docker exec NC grep "$id" /etc/hosts | awk '{print $1}'
}

connect_nextcloud_to_miab() {
    #
    # integrate Nextcloud with MiaB-LDAP
    #    
    # add MiaB-LDAP's ca_certificate.pem to containers's trusted cert
    # list (because setup/ssl.sh created its own self-signed ca)
    H2 "docker: update trusted CA list"
    docker cp \
           $STORAGE_ROOT/ssl/ca_certificate.pem \
           NC:/usr/local/share/ca-certificates/mailinabox.crt \
        || die "docker: copy ca_certificate.pem failed"
    docker exec NC update-ca-certificates \
        || die "docker: update-ca-certificates failed"

    # execute the script that sets up Nextcloud
    H2 "docker: run connect-nextcloud-to-miab.sh"
    docker cp setup/mods.available/connect-nextcloud-to-miab.sh NC:/tmp \
        || die "docker: cp connect-nextcloud-to-miab.sh failed"
    docker exec NC /tmp/connect-nextcloud-to-miab.sh \
           . \
           "$NC_ADMIN_USER" \
           "$NC_ADMIN_PASSWORD" \
           "$PRIMARY_HOSTNAME" \
           "$LDAP_NEXTCLOUD_PASSWORD" \
        || die "docker: error running connect-nextcloud-to-miab.sh"
}



do_upgrade() {
    # initialize test system
    init "$@"

    # we install w/o remote nextcloud first so we can add
    # a user w/contacts and ensure the contact exists in the
    # new system
    disable_miab_mod "remote-nextcloud"

    # install w/o remote Nextcloud
    miab_ldap_install "$@"
        
    # install Nextcloud in a Docker container. exports NC_HOST_SRC_IP.
    install_nextcloud_docker
    
    H1 "Enable the remote-nextcloud mod"
    enable_miab_mod "remote-nextcloud" \
        || die "Could not enable remote-nextcloud mod"

    # re-run setup (miab_ldap_install) to use the remote Nextcloud
    miab_ldap_install

    # connect the remote Nextcloud to miab
    H1 "Connect Nextcloud to MiaB-LDAP (configure user_ldap)"
    connect_nextcloud_to_miab
}


do_default() {
    # initialize test system
    init

    # install Nextcloud in a Docker container. exports NC_HOST_SRC_IP.
    export PRIVATE_IP=$(source setup/functions.sh; get_default_privateip 4)
    install_nextcloud_docker

    H1 "Enable remote-nextcloud mod"
    enable_miab_mod "remote-nextcloud" \
        || die "Could not enable remote-nextcloud mod"
    
    # run setup to use the remote Nextcloud (doesn't need to be available)
    miab_ldap_install "$@"

    # connect the remote Nextcloud to miab
    H1 "Connect Nextcloud to MiaB-LDAP (configure user_ldap)"
    connect_nextcloud_to_miab
}





case "$1" in
    upgrade )
        # Runs this sequence:
        #   1. setup w/o remote nextcloud
        #   2. if an additional argument is given, populate the MiaB
        #      installation
        #   3. install a remote nextcloud
        #   4. enable remote-nextcloud mod
        #   5. re-run setup
        #

        shift
        do_upgrade "$@"
        ;;

    "" | default )
        # Runs this sequence:
        #   1. setup w/remote nextcloud
        #   2. install and connect the remote nextcloud
        do_default
        ;;
    
    * )
        echo "Unknown option $1"
        exit 1
        ;;
esac


