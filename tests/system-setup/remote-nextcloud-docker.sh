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
    echo "Usage: $(basename "$0") [\"before-miab-install\"|\"miab-install\"|\"after-miab-install\"]"
    echo "Install MiaB-LDAP and a remote Nextcloud running under docker exposed as localhost:8000"
    echo "With no arguments, all three stages are run."
    exit 1
}

# ensure working directory
if [ ! -d "tests/system-setup" ]; then
    echo "This script must be run from the MiaB root directory"
    exit 1
fi

# load helper scripts
. "tests/system-setup/setup-defaults.sh" \
    || die "Could not load setup-defaults"
. "tests/system-setup/setup-funcs.sh" \
    || die "Could not load setup-funcs"

# ensure running as root
if [ "$EUID" != "0" ]; then
    die "This script must be run as root (sudo)"
fi



before_miab_install() {
    H1 "BEFORE MIAB-LDAP INSTALL"

    H2 "Update /etc/hosts"
    #update_hosts_for_private_ip || die "Could not update /etc/hosts"
    set_system_hostname || die "Could not set hostname"

    # update system time
    H2 "Set system time"
    update_system_time || echo "Ignoring error..."
    
    # update package lists before installing anything
    H2 "apt-get update"
    wait_for_apt
    apt-get update -qq || die "apt-get update failed!"

    # upgrade packages - if we don't do this and something like bind
    # is upgraded through automatic upgrades (because maybe MiaB was
    # previously installed), it may cause problems with the rest of
    # the setup, such as with name resolution failures
    if is_false "$TRAVIS"; then
        H2 "apt-get upgrade"
        wait_for_apt
        apt-get upgrade -qq || die "apt-get upgrade failed!"
    fi
    
    # install prerequisites
    H2 "QA pre-setup prerequisites"
    install_pre_setup_qa_prerequisites \
        || die "Error installing QA prerequisites"

    # enable the remote Nextcloud setup mod, which tells MiaB-LDAP to use
    # the remote Nextcloud for calendar and contacts instead of the
    # MiaB-installed one
    H2 "Create setup/mods.d/remote-nextcloud.sh symbolic link"
    if [ ! -e "setup/mods.d/remote-nextcloud.sh" ]; then
        ln -s "../mods.available/remote-nextcloud.sh" "setup/mods.d/remote-nextcloud.sh" || die "Could not create remote-nextcloud.sh symlink"
    fi
    
    # install Docker
    H2 "Install Docker"
    install_docker || die "Could not install Docker! ($?)"
}


miab_install() {
    H1 "MIAB-LDAP INSTALL"
    if ! setup/start.sh; then
        H1 "OUTPUT OF SELECT FILES"
        dump_log "/var/log/syslog" 100
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
           --env SMTP_FROM_ADDRESS="$(awk -F@ '{print $1}' <<< "$EMAIL_ADDR")" \
           --env MAIL_DOMAIN="$(awk -F@ '{print $2}' <<< "$EMAIL_ADDR")" \
           nextcloud:latest \
        || die "Docker run failed!"

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
    echo -n "Waiting ..."
    local count=0
    while true; do
        if [ $count -ge 10 ]; then
            echo "FAILED"
            die "Giving up"
        fi
        sleep 6
        let count+=1
        if [ $(docker exec NC php -n -r "include 'config/config.php'; print \$CONFIG['installed']?'true':'false';") == "true" ]; then
            echo "ok"
            break
        fi
        echo -n "${count}..."
    done
    
    # install and enable Nextcloud and apps
    H2 "docker: install Nextcloud calendar app"
    docker exec -u www-data NC ./occ app:install calendar \
        || die "docker: installing calendar app failed"
    H2 "docker: install Nextcloud contacts app"
    docker exec -u www-data NC ./occ app:install contacts \
        || die "docker: installing contacts app failed"
    H2 "docker: enable user_ldap"
    docker exec -u www-data NC ./occ app:enable user_ldap \
        || die "docker: enabling user_ldap failed"

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
# process command line
#

case "$1" in
    before-miab-install )
        before_miab_install
        ;;
    after-miab-install )
        after_miab_install
        ;;
    miab-install )
        miab_install
        ;;
    "" )
        before_miab_install
        miab_install
        after_miab_install
        ;;
    * )
        
        usage
        ;;
esac
