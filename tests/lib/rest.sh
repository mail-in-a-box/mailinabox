#
# REST helper functions
#
# requirements:
#   system packages: [ curl ]
#   lib scripts: [ color-output.sh ]
#

rest_urlencoded() {
	# Issue a REST call having data urlencoded
    #
    # eg: rest_urlencoded POST /admin/mail/users/add "email=alice@abc.com" "password=secret"
    #
    # When providing a URI (/mail/users/add) and not a URL
    # (https://host/mail/users/add), PRIMARY_HOSTNAME must be set!
    #
    # The function will set the following global variables regardless
    # of exit c ode:
    #     REST_HTTP_CODE
    #     REST_OUTPUT
    #     REST_ERROR
    # 
    # Return values:
    #   0 indicates success (curl returned 0 or a code deemed to be
    #     successful and HTTP status is >=200  but <300)
    #   1 curl returned with non-zero code that indicates and error
    #   2 the response status was <200 or >= 300
    #
    # Messages, errors, and output are all sent to stderr, there is no
    # stdout output
    #   
	local verb="$1" # eg "POST"
	local uri="$2"  # eg "/mail/users/add"
	local auth_user="$3"
	local auth_pass="$4"
	shift; shift; shift; shift  # remaining arguments are data or curl args

	local url
    case "$uri" in
        http:* | https:* )
            url="$uri"
            ;;
        * )
            url="https://$PRIMARY_HOSTNAME${uri}"
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
                    data+=("--data-urlencode" "$item");
                else
                    data+=("$item")
                fi
                ;;
            * )
                onlydata="true"
                data+=("--data-urlencode" "$item");
                ;;
        esac
    done

	echo "spawn: curl -w \"%{http_code}\" -X $verb --user \"${auth_user}:xxx\" ${data[@]} $url" 1>&2
	output=$(curl -s -S -w "%{http_code}" -X $verb --user "${auth_user}:${auth_pass}" "${data[@]}" $url)
	local code=$?

	# http status is last 3 characters of output, extract it
	REST_HTTP_CODE=$(awk '{S=substr($0,length($0)-2)} END {print S}' <<<"$output")
	REST_OUTPUT=$(awk 'BEGIN{L=""}{ if(L!="") print L; L=$0 } END { print substr(L,1,length(L)-3) }' <<<"$output")
	REST_ERROR=""
	[ -z "$REST_HTTP_CODE" ] && REST_HTTP_CODE="000"

	if [ $code -ne 0 ]; then
		if [ $code -eq 56 -a $REST_HTTP_CODE -eq 200 ]; then
			# this is okay, I guess. happens sometimes during
			# POST /admin/mail/aliases/remove
			# 56=Unexpected EOF
			echo "Ignoring curl return code 56 due to 200 status" 1>&2
			
		elif [ $code -ne 16 -o $REST_HTTP_CODE -ne 200 ]; then
			# any error code will fail the rest call except for a 16
			# with a 200 HTTP status.
			# 16="a problem was detected in the HTTP2 framing layer. This is somewhat generic and can be one out of several problems"
			REST_ERROR="CURL failed with code $code"
			echo "${F_DANGER}$REST_ERROR${F_RESET}" 1>&2
			echo "$output" 1>&2
			return 1
		fi
	fi
	if [ $REST_HTTP_CODE -lt 200 -o $REST_HTTP_CODE -ge 300 ]; then
		REST_ERROR="REST status $REST_HTTP_CODE: $REST_OUTPUT"
		echo "${F_DANGER}$REST_ERROR${F_RESET}" 1>&2
		return 2
	fi
	echo "CURL succeded, HTTP status $REST_HTTP_CODE" 1>&2
	echo "$output" 1>&2
	return 0	
}
