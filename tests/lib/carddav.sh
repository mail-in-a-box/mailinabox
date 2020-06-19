#
# requires:
#    system packages: [ curl, python3, sqlite3 ]
#    scripts: [ color-output.sh, misc.sh, locations.sh ]
#
# ASSETS_DIR: where the assets directory is located (defaults to
# tests/assets)
#

nextcloud_url() {
    # eg: http://localhost/cloud/
    carddav_url | sed 's|\(.*\)/remote.php/.*|\1/|'
}

carddav_url() {
    # get the carddav url as configured in z-push for the user specified
    # eg: http://localhost/cloud/remote.php/dav/addressbooks/users/admin/contacts/
    local user="${1:-%u}"
    local path="${2:-CARDDAV_DEFAULT_PATH}"
    local php="include \"$ZPUSH_DIR/backend/carddav/config.php\"; print CARDDAV_PROTOCOL . \"://\" . CARDDAV_SERVER . \":\" . CARDDAV_PORT . "
    php="$php$path;"
    local url
    url="$(php -n -r "$php")"
    [ $? -ne 0 ] && die "Unable to run php to extract carddav url from z-push"
    sed "s/%u/$user/" <<< "$url"
}

carddav_rest() {
    # issue a CardDAV rest call to Nextcloud
    # SEE: https://tools.ietf.org/html/rfc6352
    #
    # The function will set the following global variables regardless
    # of exit code:
    #     REST_HTTP_CODE
    #     REST_OUTPUT
    #     REST_ERROR
    #     REST_ERROR_BRIEF
    # 
    # Return values:
    #   0 indicates success (curl returned 0 or a code deemed to be
    #     successful and HTTP status is >=200  but <300)
    #   1 curl returned with non-zero code that indicates and error
    #   2 the response status was <200 or >= 300
    #
    # Debug messages are sent to stderr
    #   
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
        http* )
            url="$uri"
            ;;
        * )
            url="$(carddav_url "$auth_user")${uri#/}"
            ;;
    esac
    
    local data=()
	local item output onlydata="false"
	
	for item; do
        case "$item" in
            -- )
                onlydata="true"
                ;;
            --* )
                # curl argument
                if $onlydata; then
                    data+=("--data" "$item");
                else
                    data+=("$item")
                fi
                ;;
            * )
                onlydata="true"
                data+=("--data" "$item");
                ;;
        esac
    done
    
    local ct
    case "${data[1]}" in
        BEGIN:VCARD* )
            ct="text/vcard"
            ;;
        * )
            ct='text/xml; charset="utf-8"'
    esac

    local tmp1="/tmp/curl.$$.tmp"
    
    echo "spawn: curl -w \"%{http_code}\" -X $verb -H 'Content-Type: $ct' --user \"${auth_user}:xxx\" ${data[@]} \"$url\"" 1>&2
	output=$(curl -s -S -w "%{http_code}" -X $verb -H "Content-Type: $ct" --user "${auth_user}:${auth_pass}" "${data[@]}" "$url" 2>$tmp1)
	local code=$?

	# http status is last 3 characters of output, extract it
	REST_HTTP_CODE=$(awk '{S=substr($0,length($0)-2)} END {print S}' <<<"$output")
	REST_OUTPUT=$(awk 'BEGIN{L=""}{ if(L!="") print L; L=$0 } END { print substr(L,1,length(L)-3) }' <<<"$output")
	REST_ERROR=""
    REST_ERROR_BRIEF=""
	[ -z "$REST_HTTP_CODE" ] && REST_HTTP_CODE="000"

    if [ $code -ne 0 -o \
               $REST_HTTP_CODE -lt 200 -o \
               $REST_HTTP_CODE -ge 300 ]
    then
        if [ $code -ne 0 -a "$REST_HTTP_CODE" == "000" ]; then
            REST_ERROR="exit code $code"
            REST_ERROR_BRIEF="$REST_ERROR"
        else
		    REST_ERROR="REST status $REST_HTTP_CODE: $REST_OUTPUT"
            REST_ERROR_BRIEF=$(python3 -c "import xml.etree.ElementTree as ET; print(ET.fromstring(r'''$REST_OUTPUT''').find('s:message',{'s':'http://sabredav.org/ns'}).text)" 2>/dev/null)
            if [ -z "$REST_ERROR_BRIEF" ]; then
                REST_ERROR_BRIEF="$REST_ERROR"
            else
                REST_ERROR_BRIEF="$REST_HTTP_CODE: $REST_ERROR_BRIEF"
            fi
            if [ $code -ne 0 ]; then
                REST_ERROR_BRIEF="exit code $code: $REST_ERROR_BRIEF"
                REST_ERROR="exit code $code: $REST_ERROR"
            fi
        fi

        if [ -s $tmp1 ]; then
            REST_ERROR="$REST_ERROR: $(cat $tmp1)"
            REST_ERROR_BRIEF="$REST_ERROR_BRIEF: $(cat $tmp1)"
        fi
        rm -f $tmp1
        
		echo "${F_DANGER}$REST_ERROR${F_RESET}" 1>&2
		[ $code -ne 0 ] && return 1
        return 2
	fi
    
	echo "CURL succeded, HTTP status $REST_HTTP_CODE" 1>&2
	echo "$output" 1>&2
    rm -f $tmp1
	return 0    
}


carddav_ls() {
    # place all .vcf files into global FILES
    # debug messages are sent to stderr
    local user="$1"
    local pass="$2"
    shift; shift
    FILES=()
    if ! carddav_rest PROPFIND "" "$user" "$pass" $@
    then
        return 1
    fi
    
    FILES=( $(python3 -c "import xml.etree.ElementTree as ET; [print(el.find('d:href',{'d':'DAV:'}).text) for el in ET.fromstring(r'''$REST_OUTPUT''').findall('d:response',{'d':'DAV:'}) if el.find('d:href',{'d':'DAV:'}) is not None]") )

    local idx=${#FILES[*]}
    let idx-=1
    while [ $idx -ge 0 ]; do
        # remove non .vcf entries, take basename contact href
        case "${FILES[$idx]}" in
            *.vcf )
                FILES[$idx]=$(basename "${FILES[$idx]}")
                ;;
            * )
                unset "FILES[$idx]"
                ;;
        esac
        let idx-=1
    done
}


carddav_make_addressbook() {
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
    local url="$(carddav_url "$user" CARDDAV_PATH)"
    carddav_rest MKCOL "$url" "$user" "$pass" "$xml"
}


carddav_add_contact() {
    # debug messages are sent to stderr
    local user="$1"
    local pass="$2"
    local c_name="$3"
    local c_phone="$4"
    local c_email="$5"
    local c_uid="${6:-$(generate_uuid)}"
    shift; shift; shift; shift; shift; shift
    
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
    carddav_rest PUT "$c_uid.vcf" "$user" "$pass" $@ -- "$vcard"
}


carddav_delete_contact() {
    local user="$1"
    local pass="$2"
    local c_uid="$3"
    shift; shift; shift
    carddav_rest DELETE "$c_uid.vcf" "$user" "$pass" $@
}


roundcube_force_carddav_refresh() {
    local user="$1"
    local pass="$2"
    local assets_dir="${ASSETS_DIR:-tests/assets}"
    local code
    if ! cp "$assets_dir/mail/roundcube/carddav_refresh.sh" $RCM_DIR/bin
    then
        return 1
    fi
    pushd "$RCM_DIR" >/dev/null
    bin/carddav_refresh.sh "$user" "$pass"
    code=$?
    popd >/dev/null
    return $code
}


roundcube_carddav_contact_exists() {
    # returns 0 if contact exists
    #         1 if contact does not exist
    #         2 if an error occurred
    # stderr receives error messages
    local user="$1"
    local pass="$2"
    local c_uid="$3"
    local db="${4:-$STORAGE_ROOT/mail/roundcube/roundcube.sqlite}"
    local output
    output="$(sqlite3 "$db" "select name from carddav_contacts where cuid='$c_uid'")"
    [ $? -ne 0 ] && return 2
    if [ -z "$output" ]; then
        return 1
    else
        return 0
    fi
}


roundcube_dump_contacts() {
    local db="${1:-$STORAGE_ROOT/mail/roundcube/roundcube.sqlite}"
    local cols="${2:-name,cuid}"
    sqlite3 "$db" "select $cols FROM carddav_contacts"
}

