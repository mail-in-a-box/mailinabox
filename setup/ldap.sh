#!/bin/bash
# -*- indent-tabs-mode: t; tab-width: 4; -*-

#
# LDAP server (slapd) for user authentication and directory services
#
source setup/functions.sh # load our functions
source setup/functions-ldap.sh # load our ldap-specific functions
source /etc/mailinabox.conf # load global vars

ORGANIZATION="Mail-In-A-Box"
LDAP_DOMAIN="mailinabox"
LDAP_BASE="dc=mailinabox"
LDAP_SERVICES_BASE="ou=Services,$LDAP_BASE"
LDAP_CONFIG_BASE="ou=Config,$LDAP_BASE"
LDAP_DOMAINS_BASE="ou=domains,$LDAP_CONFIG_BASE"
LDAP_PERMITTED_SENDERS_BASE="ou=permitted-senders,$LDAP_CONFIG_BASE"
LDAP_USERS_BASE="ou=Users,${LDAP_BASE}"
LDAP_ALIASES_BASE="ou=aliases,${LDAP_USERS_BASE}"
LDAP_ADMIN_DN="cn=admin,dc=mailinabox"

STORAGE_LDAP_ROOT="$STORAGE_ROOT/ldap"
MIAB_SLAPD_DB_DIR="$STORAGE_LDAP_ROOT/db"
MIAB_SLAPD_CONF="$STORAGE_LDAP_ROOT/slapd.d"
MIAB_INTERNAL_CONF_FILE="$STORAGE_LDAP_ROOT/miab_ldap.conf"

SERVICE_ACCOUNTS=(LDAP_DOVECOT LDAP_POSTFIX LDAP_WEBMAIL LDAP_MANAGEMENT LDAP_NEXTCLOUD)


#
# Helper functions
#

ldap_debug_flag() {
	[ ${verbose:-0} -gt 1 ] && echo "-d 1"
}

wait_slapd_start() {
	# Wait for slapd to start...
	say_verbose -n "Waiting for slapd to start"
	local let elapsed=0
	until nc -z -w 4 127.0.0.1 389
	do
		[ $elapsed -gt 30 ] && die "Giving up waiting for slapd to start!"
		[ $elapsed -gt 0 ] && say_verbose -n "...${elapsed}"
		sleep 2
		let elapsed+=2
	done
	say_verbose "...ok"
}

_add_if_missing() {
	local var="$1"
	local val="$2"
	local conf="$MIAB_INTERNAL_CONF_FILE"
	if [ $(grep -c "^${var}=" "$conf") -eq 0 ]; then
		echo "${var}=\"${val}\"" >> "$conf"
	fi
}

create_miab_conf() {
	# create (if non-existing) or load (existing) ldap/miab_ldap.conf
	if [ ! -e "$MIAB_INTERNAL_CONF_FILE" ]; then
		say_verbose "Generating a new $MIAB_INTERNAL_CONF_FILE"
		mkdir -p "$(dirname $MIAB_INTERNAL_CONF_FILE)"
		touch "$MIAB_INTERNAL_CONF_FILE"
	fi

	# ensure all required values exist, and if not set to default values
	_add_if_missing LDAP_SERVER 127.0.0.1
	_add_if_missing LDAP_SERVER_PORT 389
	_add_if_missing LDAP_SERVER_STARTTLS no
	_add_if_missing LDAP_SERVER_TLS no
	_add_if_missing LDAP_URL ldap://127.0.0.1/
	_add_if_missing LDAP_BASE "${LDAP_BASE}"
	_add_if_missing LDAP_SERVICES_BASE "${LDAP_SERVICES_BASE}"
	_add_if_missing LDAP_CONFIG_BASE "${LDAP_CONFIG_BASE}"
	_add_if_missing LDAP_DOMAINS_BASE "${LDAP_DOMAINS_BASE}"
	_add_if_missing LDAP_PERMITTED_SENDERS_BASE "${LDAP_PERMITTED_SENDERS_BASE}"
	_add_if_missing LDAP_USERS_BASE "${LDAP_USERS_BASE}"
	_add_if_missing LDAP_ALIASES_BASE "${LDAP_ALIASES_BASE}"
	_add_if_missing LDAP_ADMIN_DN "${LDAP_ADMIN_DN}"
	_add_if_missing LDAP_ADMIN_PASSWORD "$(generate_password 64)"

	# add service account credentials
	local prefix
	for prefix in ${SERVICE_ACCOUNTS[*]}
	do
		local cn=$(awk -F_ '{print tolower($2)}' <<< $prefix)
		_add_if_missing "${prefix}_DN" "cn=$cn,$LDAP_SERVICES_BASE"
		_add_if_missing "${prefix}_PASSWORD" "$(generate_password 64)"
	done
	
	chmod 0640 "$MIAB_INTERNAL_CONF_FILE"
	. "$MIAB_INTERNAL_CONF_FILE"
}


create_directory_containers() {
	# create organizationUnit containers
	local basedn
	for basedn in "$LDAP_SERVICES_BASE" "$LDAP_CONFIG_BASE" "$LDAP_DOMAINS_BASE" "$LDAP_PERMITTED_SENDERS_BASE" "$LDAP_USERS_BASE" "$LDAP_ALIASES_BASE"; do
		# add ou container
		get_attribute "$basedn" "objectClass=*" "ou" base
		if [ -z "$ATTR_DN" ]; then
			say_verbose "Adding $basedn"
			ldapadd -H ldap://127.0.0.1/ -x -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" >/dev/null <<EOF
dn: $basedn
objectClass: organizationalUnit
ou: $(awk -F'[=,]' '{print $2}' <<< $basedn)
EOF
		fi
	done
}

create_service_accounts() {
	# create service accounts. service accounts have special access
	# rights, generally read-only to users, aliases, and configuration
	# subtrees (see apply_access_control)
	
	local prefix dn pass
	for prefix in ${SERVICE_ACCOUNTS[*]}
	do
		eval "dn=\$${prefix}_DN"
		eval "pass=\$${prefix}_PASSWORD"
		get_attribute "$dn" "objectClass=*" "cn" base
		say_debug "SERVICE_ACCOUNT $dn"
		if [ -z "$ATTR_DN" ]; then
			local cn=$(awk -F'[=,]' '{print $2}' <<< $dn)
			say_verbose "Adding service account: $dn"
			ldapadd -H ldap://127.0.0.1/ -x -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" >/dev/null <<EOF
dn: $dn
objectClass: simpleSecurityObject
objectClass: organizationalRole
cn: $cn
description: ${cn} service account
userPassword: $(slappasswd_hash "$pass")
EOF
		fi
	done
	
}


install_system_packages() {
	# install required deb packages, generate admin credentials
	# and apply them to the installation
	create_miab_conf
	
	# Set installation defaults to avoid interactive dialogs. See
	# /var/lib/dpkg/info/slapd.templates for a list of what can be set
	debconf-set-selections <<EOF
slapd shared/organization string ${ORGANIZATION}
slapd slapd/domain string ${LDAP_DOMAIN}
slapd slapd/password1 password ${LDAP_ADMIN_PASSWORD}
slapd slapd/password2 password ${LDAP_ADMIN_PASSWORD}
EOF
	
	# Install packages
	say "Installing OpenLDAP server..."
	
	# we must install slapd without DEBIAN_FRONTEND=noninteractive or
	# debconf selections are ignored
	hide_output apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" install slapd

	# install additional packages
	apt_install ldap-utils python3-ldap3 ca-certificates xz-utils

	# If slapd was not installed by us, the selections above did
	# nothing.  To check this we see if SLAPD_CONF in
	# /etc/default/slapd is empty and that the olc does not have our
	# database. We could do 2 things in this situation:
	#    1. ask the user for the current admin password and add our domain
	#    2. reconfigure and wipe out the current database
	# we do #2 ....
	local SLAPD_CONF=""
	eval "$(grep ^SLAPD_CONF= /etc/default/slapd)"
	local cursuffix="$(slapcat -b "cn=config" | grep "^olcSuffix: ")"
	say_debug "current slapd suffix=$cursuffix"
	if [ -z "$SLAPD_CONF" ] &&
		   ! grep "$LDAP_DOMAIN" <<<"$cursuffix" >/dev/null
	then
		mkdir -p /var/backup
		local tgz="/var/backup/slapd-$(date +%Y%m%d-%H%M%S).tgz"
		(cd /var/lib/ldap; tar czf "$tgz" .)
		chmod 600 "$tgz"
		rm /var/lib/ldap/*
		say "Reininstalling slapd! - existing database saved in $tgz"
		dpkg-reconfigure --frontend=noninteractive slapd
	fi

	# Clear passwords out of debconf
	debconf-set-selections <<EOF
slapd slapd/password1 password
slapd slapd/password2 password
EOF

	# Ensure slapd is running
	systemctl start slapd && wait_slapd_start

	# Change the root password hash format in the server from slapd's
	# default {SSHA} to SHA-512 {CRYPT} with 16 characters of salt
	get_attribute "cn=config" "olcSuffix=${LDAP_BASE}" "olcRootPW"
	if [ ${#ATTR_VALUE[*]} -eq 1 -a $(grep -c "{SSHA}" <<< "$ATTR_VALUE") -eq 1 ]; then
		say_verbose "Updating root hash to SHA512-CRYPT"
		local hash=$(slappasswd_hash "$LDAP_ADMIN_PASSWORD")
		ldapmodify -Q -Y EXTERNAL -H ldapi:/// >/dev/null <<EOF
dn: $ATTR_DN
replace: olcRootPW
olcRootPW: $hash
EOF
	fi

	get_attribute "cn=config" "olcSuffix=${LDAP_BASE}" "olcRootDN"
	if [ "$ATTR_VALUE" != "$LDAP_ADMIN_DN" ]; then
		say ""
		say "UNEXPECTED: oldRootDN under $ATTR_DN"
		say "  is set to: $ATTR_VALUE"
		say "  expected : $LDAP_ADMIN_DN"
		die
	fi		
}

relocate_slapd_data() {
	#
	# Move current ldap databases to user-data (eg. new install). A
	# new slapd installation places the ldap configuration database in
	# /etc/ldap/slapd.d and schema database in /var/lib/ldap. So that
	# backups include the ldap database, move everything to user-data.
	#
	# On entry:
	#	SLAPD_CONF must point to the current slapd.d directory
	#	   (see /etc/default/slapd)
	#	Global variables as defined above must be set
	#	The slapd service must be running
	#
	# On success:
	#	Config and data will be relocated to the new locations
	#
	say_verbose "Relocate ldap databases from current locations to user-data"

	# Get the current database location from olc
	get_attribute "cn=config" "olcSuffix=${LDAP_BASE}" "olcDbDirectory"
	local DN="$ATTR_DN"
	local DB_DIR="$ATTR_VALUE"
	if [ -z "$DN" ]; then
		say_verbose ""
		say_verbose "ACK! ${LDAP_BASE} does not exist in the LDAP server!!!"
		say_verbose "Something is amiss!!!!!"
		say_verbose "... to ensure no data is lost, please manually fix the problem"
		say_verbose "	 by running 'sudo dpkg-reconfigure slapd'"
		say_verbose ""
		say_verbose "CAUTION: running dbpg-reconfigure will remove ALL data"
		say_verbose "for the existing domain!"
		say_verbose ""
		die "Unable to continue!"
	fi

	# Exit if destination directories are non-empty
	[ ! -z "$(ls -A $MIAB_SLAPD_CONF)" ] && die "Cannot relocate system LDAP because $MIAB_SLAPD_CONF is not empty!"
	[ ! -z "$(ls -A $MIAB_SLAPD_DB_DIR)" ] && die "Cannot relocate system LDAP because $MIAB_SLAPD_DB_DIR is not empty!"

	# Stop slapd
	say_verbose ""
	say_verbose "Relocating ldap databases:"
	say_verbose "	from: "
	say_verbose "	   CONF='${SLAPD_CONF}'"
	say_verbose "		DB='${DB_DIR}'"
	say_verbose "	to:"
	say_verbose "	   CONF=${MIAB_SLAPD_CONF}"
	say_verbose "		 DB=${MIAB_SLAPD_DB_DIR}"	
	say_verbose ""
	say_verbose "Stopping slapd"
	systemctl stop slapd || die "Could not stop slapd"
	
	# Modify the path to dc=mailinabox's database directory
	say_verbose "Dump config database"
	local TMP="/tmp/miab_relocate_ldap.ldif"
	slapcat -F "${SLAPD_CONF}" -l "$TMP" -n 0 || die "slapcat failed"
	awk -e "/olcDbDirectory:/ {print \$1 \"$MIAB_SLAPD_DB_DIR\"} !/^olcDbDirectory:/ { print \$0}" $TMP > $TMP.2
	rm -f "$TMP"

	# Copy the existing database files
	say_verbose "Copy database files ($DB_DIR => $MIAB_SLAPD_DB_DIR)"
	cp -p "${DB_DIR}"/* "${MIAB_SLAPD_DB_DIR}" || die "Could not copy files '${DB_DIR}/*' to '${MIAB_SLAPD_DB_DIR}'"

	# Re-create the config
	say_verbose "Create new slapd config"
	local xargs=()
	[ ${verbose:-0} -gt 0 ] && xargs+=(-d 10 -v)
	slapadd -F "${MIAB_SLAPD_CONF}" ${xargs[@]} -n 0 -l "$TMP.2" 2>/dev/null || die "slapadd failed!"
	chown -R openldap:openldap "${MIAB_SLAPD_CONF}"
	rm -f "$TMP.2"

	# Remove the old database files
	rm -f "${DB_DIR}/*"
}


schema_to_ldif() {
	# Convert a .schema file to ldif. This function follows the
	# conversion instructions found in /etc/ldap/schema/openldap.ldif
	local schema="$1"  # path or url to schema
	local ldif="$2"	   # destination file - will be overwritten
	local cn="$3"	   # schema common name, eg "postfix"
	local cat='cat'
	if [ ! -e "$schema" ]; then
		if [ -e "conf/schema/$(basename $schema)" ]; then
			schema="conf/schema/$(basename $schema)"
		else
			cat="curl -s"
		fi
	fi
	
	cat >"$ldif" <<EOF
dn: cn=$cn,cn=schema,cn=config
objectClass: olcSchemaConfig
cn: $cn
EOF

	$cat "$schema" \
		| sed s/attributeType/olcAttributeTypes:/ig \
		| sed s/objectClass/olcObjectClasses:/ig \
		| sed s/objectIdentifier/olcObjectIdentifier:/ig \
		| sed 's/\t/  /g' \
		| sed 's/^\s*$/#/g' >> "$ldif"
}

change_core_mail_syntax() {
	# output the ldif to change mail to utf8 from ia5 in the core schema
	get_attribute "cn=schema,cn=config" "(cn={0}core)" "olcAttributeTypes"
	case "${ATTR_VALUE[48]}" in
		*\'mail\'*caseIgnoreIA5Match* )
			newval=$(sed 's/SYNTAX[ \t][^ ]*/SYNTAX 1.3.6.1.4.1.1466.115.121.1.15/g' <<<"${ATTR_VALUE[48]}" |
					 sed 's/caseIgnoreIA5Match/caseIgnoreMatch/g' |
					 sed 's/caseIgnoreIA5SubstringsMatch/caseIgnoreSubstringsMatch/g')
			cat <<EOF
dn: cn={0}core,cn=schema,cn=config
changetype: modify
delete: olcAttributeTypes
olcAttributeTypes: ${ATTR_VALUE[48]}
-
add: olcAttributeTypes
olcAttributeTypes: $newval
EOF
			;;
	esac
}


add_schemas() {
	# Add necessary schema's for MiaB operaion		 
	#
	# Note: the postfix schema originally came from the ldapadmin
	# project (GPL)(*), but has been modified to support the needs of
	# this project.
	#	see: http://ldapadmin.org
	#		 http://ldapadmin.org/docs/postfix.schema
	#		 http://www.postfix.org/LDAP_README.html
	for cn in "postfix" "mfa-totp" "namedProperties"; do
		schema="$cn.schema"
		get_attribute "cn=schema,cn=config" "(&(cn={*}$cn)(objectClass=olcSchemaConfig))" "cn"
		if [ -z "$ATTR_DN" ]; then
			local ldif="/tmp/$cn.$$.ldif"
			schema_to_ldif "$schema" "$ldif" "$cn"
			if [ "$cn" = "postfix" ]; then
				local ldif2="/tmp/$cn.$$-2.ldif"
				change_core_mail_syntax >"$ldif2"
				echo "" >>"$ldif2"
				sed 's/^dn: cn=postfix,\(.*\)$/dn: cn=postfix,\1\nchangetype: add/g' "$ldif" >> "$ldif2"
				rm "$ldif"
				ldif="$ldif2"
			fi
			say_verbose "Adding '$cn' schema"
			[ ${verbose:-0} -gt 1 ] && cat "$ldif"
			ldapadd -Q -Y EXTERNAL -H ldapi:/// -f "$ldif" >/dev/null
			rm -f "$ldif"
		fi
	done	
}


modify_global_config() {
	#
	# Set ldap configuration attributes:
	#  IdleTimeout: seconds to wait before forcibly closing idle connections
	#  LogLevel: logging levels - see OpenLDAP docs
	#  TLS configuration
	#  Disable anonymous binds
	#
	say_verbose "Setting global ldap configuration"

	# TLS requirements:
	#
	# The 'openldap' user must have read access to the TLS private key
	# and certificate (file system permissions and apparmor). If
	# access is not configured properly, slapd retuns error code 80
	# and won't apply the TLS configuration, or won't start.
	#
	# Openldap TLS will not operate with a self-signed server
	# certificate! The server will always log "unable to get TLS
	# client DN, error=49." Ensure the certificate is signed by
	# a certification authority.
	#
	# The list of trusted CA certificates must include the CA that
	# signed the server's certificate!
	#
	# For the olcCiperSuite setting, see:
	# https://www.gnutls.org/manual/gnutls.html#Priority-Strings
	#

	ldapmodify $(ldap_debug_flag) -Q -Y EXTERNAL -H ldapi:/// >/dev/null <<EOF
dn: cn=config
##
## timeouts (1800=30 minutes) and logging
##
replace: olcIdleTimeout
olcIdleTimeout: 1800
-
replace: olcLogLevel
olcLogLevel: config stats shell
#olcLogLevel: config stats shell filter ACL
-
##
## TLS
##
replace: olcTLSCACertificateFile
olcTLSCACertificateFile: /etc/ssl/certs/ca-certificates.crt
-
replace: olcTLSCertificateFile
olcTLSCertificateFile: $STORAGE_ROOT/ssl/ssl_certificate.pem
-
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: $STORAGE_ROOT/ssl/ssl_private_key.pem
-
replace: olcTLSDHParamFile
olcTLSDHParamFile: $STORAGE_ROOT/ssl/dh2048.pem
-
# TLS ciphers. To see expanded corresponding cipher suites run:
#   gnutls-cli --priority PFS:-VERS-TLS1.0:-VERS-TLS1.1 -l
replace: olcTLSCipherSuite
olcTLSCipherSuite: PFS:-VERS-TLS1.0:-VERS-TLS1.1
-
replace: olcTLSVerifyClient
olcTLSVerifyClient: never
-
##
## Password policies - use SHA512 with 16 characters of salt
##
replace: olcPasswordHash
olcPasswordHash: {CRYPT}
-
replace: olcPasswordCryptSaltFormat
olcPasswordCryptSaltFormat: \$6\$%.16s
-
##
## Disable anonymous binds
##
replace: olcDisallows
olcDisallows: bind_anon
-
replace: olcRequires
olcRequires: authc

dn: olcDatabase={-1}frontend,cn=config
replace: olcRequires
olcRequires: authc
EOF
}


add_overlays() {
	# Apply slapd overlays - apply the commonly used member-of overlay
	# now because adding it later is harder.
	
	# Get the config dn for the database
	get_attribute "cn=config" "olcSuffix=${LDAP_BASE}" "dn"
	[ -z "$ATTR_DN" ] &&
		die "No config found for olcSuffix=$LDAP_BASE in cn=config!"
	local cdn="$ATTR_DN"

	# Add member-of overlay (man 5 slapo-memberof)
	get_attribute "cn=module{0},cn=config" "(olcModuleLoad=memberof.la)" "dn" base
	if [ -z "$ATTR_DN" ]; then
		say_verbose "Adding memberof overlay module"
		ldapmodify -Q -Y EXTERNAL -H ldapi:/// >/dev/null <<EOF
dn: cn=module{0},cn=config
add: olcModuleLoad
olcModuleLoad: memberof.la
EOF
	fi
	
	get_attribute "$cdn" "(olcOverlay=memberof)" "olcOverlay"
	if [ -z "$ATTR_DN" ]; then
		say_verbose "Adding memberof overlay to $LDAP_BASE"
		ldapadd -Q -Y EXTERNAL -H ldapi:/// >/dev/null <<EOF
dn: olcOverlay=memberof,$cdn
objectClass: olcOverlayConfig
objectClass: olcMemberOf
olcOverlay: memberof
#olcMemberOfGroupOC: mailGroup
olcMemberOfRefint: TRUE
EOF
	fi
}


add_indexes() {
	# Index mail-related attributes
	
	# Get the config dn for the database
	get_attribute "cn=config" "olcSuffix=${LDAP_BASE}" "dn"
	[ -z "$ATTR_DN" ] &&
		die "No config found for olcSuffix=$LDAP_BASE in cn=config!"
	local cdn="$ATTR_DN"

	# Add the indexes
	get_attribute "$cdn" "(objectClass=*)" "olcDbIndex" base
	local attr
	for attr in mail maildrop mailaccess dc dcIntl mailMember; do
		local type="eq" atype="" aindex=""
		[ "$attr" == "mail" ] && type="eq,sub"

		# find the existing index for the attribute
		local item
		for item in "${ATTR_VALUE[@]}"; do
			local split=($item)  # eg "mail eq"
			if [ "${split[0]}" == "$attr" ]; then
				aindex="$item"
				atype="${split[1]}"
				break
			fi
		done

		# if desired index type (eg "eq") is equal to actual type,
		# continue, no change
		[ "$type" == "$atype" ] && continue

		# replace it or add a new index if not present
		if [ ! -z "$atype" ]; then
			say_verbose "Replace index $attr ($atype -> $type)"
			ldapmodify -Q -Y EXTERNAL -H ldapi:/// >/dev/null <<EOF
dn: $cdn
delete: olcDbIndex
olcDbIndex: $aindex
-
add: olcDbIndex
olcDbIndex: $attr $type
EOF
		else
			say_verbose "Add index for attribute $attr ($type)"
			ldapmodify -Q -Y EXTERNAL -H ldapi:/// >/dev/null <<EOF
dn: $cdn
add: olcDbIndex
olcDbIndex: $attr $type
EOF
		fi
	done
}


apply_access_control() {
	# Apply access control to the mail-in-a-box databse.
	#
	# Permission restrictions:
	#	service accounts (except management):
	#	   can bind but not change passwords, including their own
	#	   can read all attributes of all users but not userPassword,
	#         totpSecret, totpMruToken, totpMruTokenTime, or totpLabel
	#	   can read config subtree (permitted-senders, domains)
	#	   no access to services subtree, except their own dn
	#	management service account:
	#	   can read and change password, shadowLastChange, and totpSecret
	#	   all other service account permissions are the same
	#	users:
	#	   can bind and change their own password
	#	   can read and change their own shadowLastChange
	#      cannot read or modify totpSecret, totpMruToken, totpMruTokenTime, totpLabel
	#	   can read attributess of other users except mailaccess, totpSecret, totpMruToken, totpMruTokenTime, totpLabel
	#	   no access to config subtree
	#	   no access to services subtree
	#

	# Get the config dn for the database
	get_attribute "cn=config" "olcSuffix=${LDAP_BASE}" "dn"
	[ -z "$ATTR_DN" ] &&
		die "No config found for olcSuffix=$LDAP_BASE in cn=config!"
	local cdn="$ATTR_DN"

	say_verbose "Setting database permissions"
	ldapmodify -Q -Y EXTERNAL -H ldapi:/// >/dev/null <<EOF
dn: $cdn
replace: olcAccess
# the next line is for nextcloud to be able to change user account
# passwords. remove it when nextcloud server issue #18406 is fixed
olcAccess: to dn.subtree="${LDAP_USERS_BASE}" attrs=userPassword
  by dn.exact="cn=management,${LDAP_SERVICES_BASE}" write
  by dn.exact="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" read
  by dn.exact="cn=nextcloud,${LDAP_SERVICES_BASE}" write
  by self =wx
  by anonymous auth
  by * none
olcAccess: to attrs=userPassword
  by dn.exact="cn=management,${LDAP_SERVICES_BASE}" write
  by dn.exact="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" read
  by dn.subtree="${LDAP_SERVICES_BASE}" none
  by self =wx
  by anonymous auth
  by * none
olcAccess: to attrs=totpSecret,totpMruToken,totpMruTokenTime,totpLabel
  by dn.exact="cn=management,${LDAP_SERVICES_BASE}" write
  by dn.exact="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" read
  by * none
olcAccess: to attrs=shadowLastChange
  by self write
  by dn.exact="cn=management,${LDAP_SERVICES_BASE}" write
  by dn.subtree="${LDAP_SERVICES_BASE}" read
  by dn.exact="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" read
  by * none
olcAccess: to attrs=mailaccess
  by dn.exact="cn=management,${LDAP_SERVICES_BASE}" write
  by dn.subtree="${LDAP_SERVICES_BASE}" read
  by dn.exact="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" read
  by * none
olcAccess: to dn.subtree="${LDAP_CONFIG_BASE}"
  by dn.exact="cn=management,${LDAP_SERVICES_BASE}" write
  by dn.subtree="${LDAP_SERVICES_BASE}" read
  by dn.exact="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" read
  by * none
olcAccess: to dn.subtree="${LDAP_SERVICES_BASE}"
  by self read
  by dn.exact="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" read
  by * none
olcAccess: to dn.subtree="${LDAP_USERS_BASE}"
  by dn.exact="cn=management,${LDAP_SERVICES_BASE}" write
  by * read
olcAccess: to *
  by * read
EOF
}



update_apparmor() {
	# Update slapd's access rights under AppArmor so that it has
	# access to database files in the user-data location
	cat > /etc/apparmor.d/local/usr.sbin.slapd <<EOF
	# database directories
	$MIAB_SLAPD_CONF/** rw,
	$MIAB_SLAPD_DB_DIR/ r,
	$MIAB_SLAPD_DB_DIR/** rwk,
	$MIAB_SLAPD_DB_DIR/alock kw,

	# certificates and keys
	$STORAGE_ROOT/ssl/* r,
EOF
	chmod 0644 /etc/apparmor.d/local/usr.sbin.slapd

	# Load settings into the kernel only if AppArmor is enabled
	if aa-status --enabled; then
		apparmor_parser -r /etc/apparmor.d/usr.sbin.slapd
	fi
}


#
# Process command line arguments -- these are here for debugging and
# testing purposes
#
process_cmdline() {
	[ -e "$MIAB_INTERNAL_CONF_FILE" ] && . "$MIAB_INTERNAL_CONF_FILE"
	
	if [ "$1" == "-d" ]; then
		# Start slapd in interactive/debug mode
		echo "!! SERVER DEBUG MODE !!"
		echo "Stopping slapd"
		systemctl stop slapd
		. /etc/default/slapd
		echo "Listening on $SLAPD_SERVICES..."
		/usr/sbin/slapd -h "$SLAPD_SERVICES" -g openldap -u openldap -F $MIAB_SLAPD_CONF -d ${2:-1}
		exit 0
		
	elif [ "$1" == "-config" ]; then
		# Apply a certain configuration
		if [ "$2" == "server" ]; then
			add_schemas
			modify_global_config
			add_overlays
			add_indexes
			apply_access_control
		elif [ "$2" == "apparmor" ]; then
			update_apparmor
		elif [ "$2" == "system-packages" ]; then
			install_system_packages
		else
			echo "Invalid: '$2'. Only 'server' and 'apparmor' supported"
			exit 1
		fi
		exit 0

	elif [ "$1" == "-search" ]; then
		# search for email addresses, distinguished names and general
		# ldap filters. Args:
		#    search filter [optional]
		#    base dn [optional]
		#    remaining args are attributes to output [optional]
		shift
		if [ $# -eq 0 ]; then
			debug_search "(objectclass=*)"
		else
			debug_search "$@"
		fi
		exit 0

	elif [ "$1" == "-schema-to-ldif" ]; then
		cn="$2"
		output="${3:-/dev/stdout}"
		schema="$cn.schema"
		schema_to_ldif "$schema" "$output" "$cn"
		exit 0

	elif [ "$1" == "-dumpdb" ]; then
		# Dump (to stdout) select ldap data and configuration
		local s=${2:-all}
		local hide_attrs="(structuralObjectClass|entryUUID|creatorsName|createTimestamp|entryCSN|modifiersName|modifyTimestamp)"
		local slapcat_args=(-F "$MIAB_SLAPD_CONF" -o ldif-wrap=no)
		[ ${verbose:-0} -gt 0 ] && hide_attrs="(_____NEVERMATCHES)"
		
		if [ "$s" == "all" ]; then
			echo ""
			echo '--------------------------------'
			slapcat ${slapcat_args[@]} -b "$LDAP_BASE" | grep -Ev "^$hide_attrs:"
		fi
		if [ "$s" == "all" -o "$s" == "config" ]; then
			echo ""
			echo '--------------------------------'
			cat "$MIAB_SLAPD_CONF/cn=config.ldif" | grep -Ev "^$hide_attrs:"
			get_attribute "cn=config" "olcSuffix=${LDAP_BASE}" "dn"
			echo ""
			slapcat ${slapcat_args[@]} -b "$ATTR_DN" | grep -Ev "^$hide_attrs:"
		fi
		if [ "$s" == "all" -o "$s" == "schema" ]; then
			echo ""
			echo '--------------------------------'
			slapcat ${slapcat_args[@]} -b "cn=schema,cn=config" | grep -Ev "^$hide_attrs:"
		fi
		if [ "$s" == "all" -o "$s" == "frontend" ]; then
			echo ""
			echo '--------------------------------'
			cat "$MIAB_SLAPD_CONF/cn=config/olcDatabase={-1}frontend.ldif" | grep -Ev "^$hide_attrs:"
		fi
		if [ "$s" == "all" -o "$s" == "module" ]; then
			echo ""
			cat "$MIAB_SLAPD_CONF/cn=config/cn=module{0}.ldif" | grep -Ev "^$hide_attrs:"
		fi
		if [ "$s" == "users" ]; then
			echo ""
			echo '--------------------------------'
			debug_search "(objectClass=mailUser)" "$LDAP_USERS_BASE"
		fi
		if [ "$s" == "aliases" ]; then
			echo ""
			echo '--------------------------------'
			local attrs=(mail member mailRoutingAddress mailMember namedProperty)
			[ ${verbose:-0} -gt 0 ] && attrs=()
			debug_search "(objectClass=mailGroup)" "$LDAP_ALIASES_BASE" ${attrs[@]}
		fi
		if [ "$s" == "permitted-senders" -o "$s" == "ps" ]; then
			echo ""
			echo '--------------------------------'
			local attrs=(mail member mailRoutingAddress rfc822MailMember)
			[ ${verbose:-0} -gt 0 ] && attrs=()
			debug_search "(objectClass=mailGroup)" "$LDAP_PERMITTED_SENDERS_BASE" ${attrs[@]}
		fi
		if [ "$s" == "domains" ]; then
			echo ""
			echo '--------------------------------'
			debug_search "(objectClass=domain)" "$LDAP_DOMAINS_BASE"
		fi
		exit 0

	elif [ "$1" == "-reset" ]; then
		#
		# Delete and remove OpenLDAP
		#
		echo ""
		echo "!!!!!			   WARNING!				  !!!!!"
		echo "!!!!!		 OPENLDAP WILL BE REMOVED	  !!!!!"
		echo "!!!!!	 ALL LDAP DATA WILL BE DESTROYED  !!!!!"
		echo ""
		echo -n "Type 'YES' to continue: "
		read ans
		if [ "$ans" != "YES" ]; then
			echo "Aborted"
			exit 1
		fi
		if [ -x /usr/sbin/slapd ]; then
			apt-get remove --purge -y slapd
			apt-get -y autoremove
			apt-get autoclean
		fi
		rm -rf "$STORAGE_LDAP_ROOT"
		rm -rf "/etc/ldap/slapd.d"
		rm -rf "/var/lib/ldap"
		rm -f "/etc/default/slapd"
		echo "Done"
		exit 0
		
	elif [ ! -z "$1" ]; then
		echo "Invalid command line argument '$1'"
		exit 1
	fi
}

[ $# -gt 0 ] && process_cmdline $@



####
#### MAIN SCRIPT CODE STARTS HERE...
####

# Run apt installs
install_system_packages

# Update the ldap schema
add_schemas

#
# Create user-data/ldap directory structure:
#	db/			  - holds slapd database for "dc=mailinabox"
#	slapd.d/	  - holds slapd configuration
#	miab_ldap.conf	- holds values for other subsystems like postfix, management, etc
#
for d in "$STORAGE_LDAP_ROOT" "$MIAB_SLAPD_DB_DIR" "$MIAB_SLAPD_CONF"; do
	mkdir -p "$d"
	chown openldap:openldap "$d"
	chmod 755 "$d"
done

# Ensure openldap can access the tls/ssl private key file
usermod -a -G ssl-cert openldap

# Ensure slapd can interact with the mailinabox database and config
update_apparmor

# Load slapd's init script startup options
. /etc/default/slapd
if [ -z "$SLAPD_CONF" ]; then
	# when not defined, slapd uses its compiled-in default directory
	SLAPD_CONF="/etc/ldap/slapd.d"
fi


# Relocate slapd databases to user-data, which is needed after a new
# installation, we're restoring from backup, or STORAGE_ROOT changes
if [ "$SLAPD_CONF" != "$MIAB_SLAPD_CONF" ]; then
	if [ -z "$(ls -A $MIAB_SLAPD_CONF)" ]; then
		# Empty destination - relocate databases
		relocate_slapd_data
	else
		# Non-empty destination - use the backup data as-is
		systemctl stop slapd
	fi
	# Tell the system startup script to use our config database
	tools/editconf.py /etc/default/slapd \
					  "SLAPD_CONF=$MIAB_SLAPD_CONF"
	systemctl start slapd || die "slapd woudn't start! try running $0 -d"
	wait_slapd_start
fi


# Configure syslog
mkdir -p /var/log/ldap
chmod 750 /var/log/ldap
chown syslog:adm /var/log/ldap
cp conf/slapd-logging.conf /etc/rsyslog.d/20-slapd.conf
chmod 644 /etc/rsyslog.d/20-slapd.conf
restart_service syslog

# Add log rotation
cat > /etc/logrotate.d/slapd <<EOF;
/var/log/ldap/slapd.log {
	weekly
	missingok
	rotate 52
	compress
	delaycompress
	notifempty
}
EOF

# Modify olc server config like TLS
# Skip this step if no ca_certificate.pem exists - this indicates
# that the system hasn't yet been migrated from sqlite
if [ -e "$STORAGE_ROOT/ssl/ca_certificate.pem" ]; then
	modify_global_config
else
	say_debug "Not enabling TLS at this time - ca_certificate hasn't been generated yet"
fi

# Add overlays and ensure mail-related attributes are indexed
add_overlays
add_indexes

# Lock down access
apply_access_control

# Create general db structure
create_directory_containers

# Create service accounts for dovecot, postfix, roundcube, etc
create_service_accounts

# Update where slapd listens for incoming requests
tools/editconf.py /etc/default/slapd \
				  "SLAPD_SERVICES=\"ldap://127.0.0.1:389/ ldaps:/// ldapi:///\""

# Restart slapd
restart_service slapd

# Dump the database daily, before backups run at 3
# This is not required, but nice to have just in case.
cat > /etc/cron.d/mailinabox-ldap << EOF
# Mail-in-a-Box
# Dump database to ldif
30 2 * * *	root	/usr/sbin/slapcat -F "$MIAB_SLAPD_CONF" -o ldif-wrap=no -b "$LDAP_BASE" | /usr/bin/xz > "$STORAGE_LDAP_ROOT/db.ldif.xz"; chmod 600 "$STORAGE_LDAP_ROOT/db.ldif.xz"
EOF
