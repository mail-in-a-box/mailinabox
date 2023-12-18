#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####

#
# requires:
#    system packages: [ curl ]
#    scripts: [ color-output.sh, misc.sh, locations.sh, carddav.sh ]
#

webdav_url() {
    local user="$1"
    local path="${2:-/}"
    # nextcloud_url is defined in carddav.sh
    local nc_url="$(nextcloud_url)"
    echo "${nc_url%/}/remote.php/dav/files/$user${path%/}"
}

webdav_rest() {
    # issue a WebDAV rest call to Nextcloud
    #
    # eg: webdav_rest PROPFIND / qa@abc.com Test_1234
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
        http* )
            url="$uri"
            ;;
        * )
            url="$(webdav_url "$auth_user")${uri#/}"
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
    
    local ct='text/xml; charset="utf-8"'
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
