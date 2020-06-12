# -*- indent-tabs-mode: t; tab-width: 4; -*-
#	
# Test the setup modification script setup/mods.available/remote-nextcloud.sh
# Prerequisites:
#
#    - Nextcloud is already installed and MiaB-LDAP is already
#      configured to use it.
#
#      ie. remote-nextcloud.sh was run on MiaB-LDAP by
#          setup/start.sh because there was a symbolic link from
#          local/remote-nextcloud.sh to the script in
#          mods.available
#
#    - The remote Nextcloud has been configured to use MiaB-LDAP
#      for users and groups.
#
#      ie. remote-nextcloud-use-miab.sh was copied to the remote Nextcloud
#      server and was run successfully there
#

is_configured() {
    . /etc/mailinabox_mods.conf
    if [ $? -ne 0 -o -z "$NC_HOST" ]; then
        return 1
    fi
    return 0
}

assert_is_configured() {
    if ! is_configured; then
        test_failure "remote-nextcloud is not configured"
        return 1
    fi
    return 0
}


nextcloud_url() {
    # eg: http://localhost/cloud/
    carddav_url | sed 's|\(.*\)/remote.php/.*|\1/|'
}

carddav_url() {
    # get the carddav url as configured in z-push for the user specified
    # eg: http://localhost/cloud/remote.php/dav/addressbooks/users/admin/contacts/
    local user="${1:-%u}"
    local path="${2:-CARDDAV_DEFAULT_PATH}"
    local php='include "/usr/local/lib/z-push/backend/carddav/config.php"; print CARDDAV_PROTOCOL . "://" . CARDDAV_SERVER . ":" . CARDDAV_PORT . '
    php="$php$path;"
    local url
    url="$(php -n -r "$php")"
    [ $? -ne 0 ] && die "Unable to run php to extract carddav url from z-push"
    sed "s/%u/$user/" <<< "$url"
}


carddav_rest() {
    # issue a CardDAV rest call to Nextcloud
    # SEE: https://tools.ietf.org/html/rfc6352
    local verb="$1"
    local uri="$2"
    local auth_user="$3"
    local auth_pass="$4"
	shift; shift; shift; shift  # remaining arguments are data

    local url
    case "$uri" in
        /* )
            url="$(nextcloud_url)${uri#/}"
            ;;
        http*)
            url="$uri"
            ;;
        * )
            url="$(carddav_url "$auth_user")${uri#/}"
            ;;
    esac
    
    local data=()
	local item output

    for item; do data+=("--data" "$item"); done

    local ct
    case "${data[1]}" in
        BEGIN:VCARD* )
            ct="text/vcard"
            ;;
        * )
            ct='text/xml; charset="utf-8"'
    esac
    
    record "spawn: curl -w \"%{http_code}\" -X $verb -H 'Content-Type: $ct' --user \"${auth_user}:xxx\" ${data[@]} \"$url\""
	output=$(curl -s -S -w "%{http_code}" -X $verb -H "Content-Type: $ct" --user "${auth_user}:${auth_pass}" "${data[@]}" "$url" 2>>$TEST_OF)
	local code=$?

	# http status is last 3 characters of output, extract it
	REST_HTTP_CODE=$(awk '{S=substr($0,length($0)-2)} END {print S}' <<<"$output")
	REST_OUTPUT=$(awk 'BEGIN{L=""}{ if(L!="") print L; L=$0 } END { print substr(L,1,length(L)-3) }' <<<"$output")
	REST_ERROR=""
	[ -z "$REST_HTTP_CODE" ] && REST_HTTP_CODE="000"

    if [ $code -ne 0 -o \
               $REST_HTTP_CODE -lt 200 -o \
               $REST_HTTP_CODE -ge 300 ]
    then
		REST_ERROR="REST status $REST_HTTP_CODE: $REST_OUTPUT"
        REST_ERROR_BRIEF=$(python3 -c "import xml.etree.ElementTree as ET; print(ET.fromstring(r'''$REST_OUTPUT''').find('s:message',{'s':'http://sabredav.org/ns'}).text)" 2>/dev/null)
        if [ -z "$REST_ERROR_BRIEF" ]; then
            REST_ERROR_BRIEF="$REST_ERROR"
        else
            REST_ERROR_BRIEF="$REST_HTTP_CODE: $REST_ERROR_BRIEF"
        fi
        if [ $code -ne 0 ]; then
            REST_ERROR_BRIEF="curl exit code $code: $REST_ERROR_BRIEF"
            REST_ERROR="curl exit code $code: $REST_ERROR"
        fi
		record "${F_DANGER}$REST_ERROR${F_RESET}"
		return 2
	fi
	record "CURL succeded, HTTP status $REST_HTTP_CODE"
	record "$output"
	return 0    
}


carddav_ls() {
    # return all .vcf files in array 'FILES'
    local user="$1"
    local pass="$2"
    carddav_rest PROPFIND "" "$user" "$pass" || return $?
    local file FILES=()
    python3 -c "import xml.etree.ElementTree as ET; [print(el.find('d:href',{'d':'DAV:'}).text) for el in ET.fromstring(r'''$REST_OUTPUT''').findall('d:response',{'d':'DAV:'}) if el.find('d:href',{'d':'DAV:'}) is not None]" |
        while read file; do
            # skip non .vcf entries
            case "$file" in
                *.vcf )
                    FILES+=( "$(basename "$file")" )
                    ;;
                * )
                    ;;
            esac
        done
}


make_collection() {
    local user="$1"
    local pass="$2"
    local name="$3"
    local desc="${4:-$name}"
    local xml="<?xml version=\"1.0\" encoding=\"utf-8\" ?>
<D:mkcol xmlns:D=\"DAV:\"
         xmlns:C=\"urn:ietf:params:xml:ns:carddav\">
  <D:set>
    <D:prop>
      <D:resourcetype>
        <D:collection/>
        <C:addressbook/>
      </D:resourcetype>
      <D:displayname>$name</D:displayname>
      <C:addressbook-description xml:lang=\"en\">$desc</C:addressbook-description>
    </D:prop>
  </D:set>
</D:mkcol>"
    record "[create address book '$name' for $user]"
    local url="$(carddav_url "$user" CARDDAV_PATH)"
    carddav_rest MKCOL "$url" "$user" "$pass" "$xml"
}



add_contact() {
    local user="$1"
    local pass="$2"
    local c_name="$3"
    local c_phone="$4"
    local c_email="$5"
    local c_uid="${6:-$(generate_uuid)}"
    local file_name="$c_uid.vcf"
    
    local vcard="BEGIN:VCARD
VERSION:3.0
UID:$c_uid
REV;VALUE=DATE-AND-OR-TIME:$(date -u +%Y%m%dT%H%M%SZ)
FN:$c_name
EMAIL;TYPE=INTERNET,PREF:$c_email
NOTE:Miab-LDAP QA
ORG:Miab-LDAP
TEL;TYPE=WORK,VOICE:$c_phone
END:VCARD"
    record "[add contact '$c_name' to $user]"
    carddav_rest PUT "$file_name" "$user" "$pass" "$vcard"
}

delete_contact() {
    local user="$1"
    local pass="$2"
    local c_uid="$3"
    local file_name="$c_uid.vcf"
    record "[delete contact with vcard uid '$c_uid' from $user]"
    carddav_rest DELETE "$file_name" "$user" "$pass"
}

force_roundcube_carddav_refresh() {
    local user="$1"
    local pass="$2"
    local code
    record "[forcing refresh of roundcube contact for $user]"
    copy_or_die assets/mail/roundcube/carddav_refresh.sh $RCM_DIR/bin
    pushd "$RCM_DIR" >/dev/null
    bin/carddav_refresh.sh "$user" "$pass" >>$TEST_OF 2>&1
    code=$?
    popd >/dev/null
    return $code
}

assert_roundcube_carddav_contact_exists() {
    local user="$1"
    local pass="$2"
    local c_uid="$3"
    local output
    record "[checking that roundcube contact with vcard UID=$c_uid exists]"
    output="$(sqlite3 $STORAGE_ROOT/mail/roundcube/roundcube.sqlite "select name from carddav_contacts where cuid='$c_uid'" 2>>$TEST_OF)"
    if [ $? -ne 0 ]; then
        test_failure "Error querying roundcube sqlite database"
        return 1
    fi
    if [ -z "$output" ]; then
        test_failure "Contact not found in Roundcube"
        record "Not found"
        record "Existing entries (name,vcard-uid):"
        output="$(sqlite3 $STORAGE_ROOT/mail/roundcube/roundcube.sqlite "select name,cuid FROM carddav_contacts" 2>>$TEST_OF)"
        return 1
    else
        record "$output"
    fi
    return 0
}


test_mail_from_nextcloud() {
    test_start "mail_from_nextcloud"
    test_end    
}

test_nextcloud_contacts() {
    test_start "nextcloud_contacts"

    assert_is_configured || test_end && return

    local alice="alice.nc@somedomain.com"
    local alice_pw="$(generate_password 16)"

	# create local user alice
	mgmt_assert_create_user "$alice" "$alice_pw"


    #
    # 1. create contact in Nextcloud - ensure it is available in Roundcube
    #    
    # this will validate Nextcloud's ability to authenticate users via
    # LDAP and that Roundcube is able to reach Nextcloud for contacts
    #

    #make_collection "$alice" "$alice_pw" "contacts"

    # add new contact to alice's Nextcloud account using CardDAV API
    local c_uid="$(generate_uuid)"
    add_contact \
        "$alice" \
        "$alice_pw" \
        "JimIno" \
        "555-1212" \
        "jim@ino.com" \
        "$c_uid" \
        || test_failure "Could not add contact for $alice in Nextcloud: $REST_ERROR_BRIEF"
    
    # force a refresh/sync of the contacts in Roundcube
    force_roundcube_carddav_refresh "$alice" "$alice_pw" || \
        test_failure "Could not refresh roundcube contacts for $alice"

    # query the roundcube sqlite database for the new contact
    assert_roundcube_carddav_contact_exists "$alice" "$alice_pw" "$c_uid"
    
    # delete the contact
    delete_contact "$alice" "$alice_pw" "$c_uid" || \
        test_failure "Unable to delete contact for $alice in Nextcloud"
    

    #
    # 2. create contact in Roundcube - ensure contact appears in Nextcloud
    #
    # TODO

    
    # clean up
    mgmt_assert_delete_user "$alice"
    
    test_end
}


suite_start "remote-nextcloud" mgmt_start

#test_mail_from_nextcloud
test_nextcloud_contacts

suite_end mgmt_end




