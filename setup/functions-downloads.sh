verify_file_sha1sum() {
    local FILE="$1"
    local HASH="$2"
    local output_error_what="${3:-}"
    CHECKSUM="$HASH  $FILE"
    if ! echo "$CHECKSUM" | sha1sum --check --strict > /dev/null; then
        if [ ! -z "$output_error_what" ]; then
            echo "------------------------------------------------------------"
		    echo "$output_error_what unexpected checksum."
		    echo "Found:"
		    sha1sum "$FILE"
		    echo
		    echo "Expected:"
		    echo "$HASH"
        fi
        return 1
    else
        return 0
    fi
}


download_link() {
    # download a link (URL) and cache it
    #
    # arguments:
    #  1: the url to download
    #
    #  2: where to send output
    #     'to-stdout': the function dumps the url contents to stdout
    #     'to-file': the function stores url contents in a file. the
    #                name of the file is returned in global variable
    #                DOWNLOAD_FILE. if caching is not enabled, the
    #                caller is responsible for deleting the file when
    #                it is no longer needed.
    #
    #  3: whether to cache the request or not    
    #      'use-cache': the download will be cached to the directory
    #                   specified in the 5th argument or to the
    #                   default directory in global variable
    #                   DOWNLOAD_CACHE_DIR
    #      'no-cache': do not cache (implied if no explicit or default
    #                  cache directory are set)
    #
    #  4: the file name to use for the cache. this could be a hash of
    #     the url to ensure uniqueness, or a name for a file that
    #     might be used across download sites. if not specified, the
    #     basename of the url is used.
    #
    #  5: the directory used to cache downloads. if not specified, the
    #     directory in DOWNLOAD_CACHE_DIR is used. If neither are set,
    #     no caching will occur.
    #
    #  6: the expected sha1 hash of the download [optional]. if output
    #  option 'to-stdout' is specified, this argument is ignored.
    #
    # The function returns:
    #    0 if successful
    #    1 if downloading failed
    #    2 for hash mismatch
    #
    local url="$1"
    local output_to="${2:-to-stdout}"
    local cache="${3:-use-cache}"
    local cache_file_name="${4:-$(basename "$url")}"
    local cache_dir="${5:-${DOWNLOAD_CACHE_DIR:-}}"
    local expected_hash="${6:-}"
    
    #say_verbose "download_link: $url (cache=$cache, output_to=$output_to)" 1>&2
    
    if [ -z "$cache_dir" ]; then
        say_debug "No cache directory configured, not caching" 1>&2
        cache="no-cache"
        
    elif [ "$cache" == "use-cache" ]; then
        mkdir -p "$cache_dir" >/dev/null
        if [ $? -ne 0 ]; then
            say_verbose "Could not create cache dir, not caching" 1>&2
            cache="no-cache"
        fi
        if [ ! -w "$cache_dir" ]; then
            say_verbose "Cache dir is not writable, not caching" 1>&2
            cache="no-cache"
        fi
    fi

    #
    # do not use the cache
    #
    if [ "$cache" != "use-cache" ]; then
        if [ "$output_to" == "to-stdout" ]; then
            DOWNLOAD_FILE=""
            DOWNLOAD_FILE_REMOVE="false"
            curl -s "$url"
            [ $? -ne 0 ] && return 1
            return 0
        
        fi
        
        DOWNLOAD_FILE="/tmp/download_file.$$.$(date +%s)"
        DOWNLOAD_FILE_REMOVE="true"
        rm -f "$DOWNLOAD_FILE"
        say_verbose "Download $url" 1>&2
        curl -s "$url" > "$DOWNLOAD_FILE"
        [ $? -ne 0 ] && return 1
        if [ ! -z "$expected_hash" ] && \
               ! verify_file_sha1sum "$DOWNLOAD_FILE" "$expected_hash" "Download of $url"
        then
		    rm -f "$DOWNLOAD_FILE"
            DOWNLOAD_FILE=""
            DOWNLOAD_FILE_REMOVE="false"
		    return 2
	    fi
        return 0
    fi

    
    #
    # use the cache
    #
    local cache_dst="$cache_dir/$cache_file_name"
    local tmp_dst="/tmp/download_file.$$.$(date +%s)"
    local code=1
    
    rm -f "$tmp_dst"
    
    if [ -e "$cache_dst" ]; then
        # cache file exists, download with 'if-modified-since'
        say_verbose "Download (if-modified-since) $url" 1>&2
        curl -z "$cache_dst" -s "$url" > "$tmp_dst"
        code=$?
        
        if [ $code -eq 0 ]; then
            if [ -s "$tmp_dst" ]; then
                # non-empty download file, cache it
                say_verbose "Modifed - caching to: $cache_dst" 1>&2
                rm -f "$cache_dst" >/dev/null && \
                    mv "$tmp_dst" "$cache_dst" >/dev/null
                code=$?
                
            else
                # cache file is up-to-date
                say_verbose "Not modifed" 1>&2
                rm -f "$tmp_dst" >/dev/null
            fi
        fi
        
    else
        # cache file does not exist
        say_verbose "Download $url" 1>&2
        curl -s "$url" > "$tmp_dst"
        code=$?
        if [ $code -eq 0 ]; then
            say_verbose "Caching to: $cache_dst" 1>&2
            rm -f "$cache_dst" >/dev/null && \
                mv "$tmp_dst" "$cache_dst" >/dev/null
            code=$?
        else
            rm -f "$tmp_dst" >/dev/null
        fi
    fi
    
    if [ $code -eq 0 ]; then
        if [ "$output_to" == "to-stdout" ]; then
            DOWNLOAD_FILE=""
            DOWNLOAD_FILE_REMOVE="false"
            cat "$cache_dst"
            [ $? -eq 0 ] && return 0
            return 1
        else
            DOWNLOAD_FILE="$cache_dst"
            DOWNLOAD_FILE_REMOVE="false"
            if [ ! -z "$expected_hash" ] && \
                   ! verify_file_sha1sum "$DOWNLOAD_FILE" "$expected_hash" "Download of $url"
            then
		        rm -f "$DOWNLOAD_FILE"
                DOWNLOAD_FILE=""
		        return 2
	        fi
        fi

        return 0
        
    else
        return 1
    fi
}


get_nc_download_url() {
    # This function returns a url where Nextcloud can be downloaded
    # for the version specified. The url is placed into global
    # variable DOWNLOAD_URL.
    #
    # Specify the version desired to 3 positions as the first argument
    # with no leading "v". eg: "19.0.0", or leave the first argument
    # blank for a url to the latest version for a fresh install. If
    # the latest minor version of a specific major version is desired,
    # set global variable REQUIRED_NC_FOR_FRESH_INSTALLS to
    # "latest-$major", for example "latest-20".
    #
    # Unless DOWNLOAD_NEXTCLOUD_FROM_GITHUB is set to "true", this
    # function always returns a link directed at Nextcloud's download
    # servers.
    #
    # requires that jq is installed on the system for Github downloads
    # when argument 1 (the nextcloud version) is not specified
    #
    # specify the archive extension to download as the second argument
    # for example, "zip" or "tar.bz2". Defaults to "tar.bz2"
    #
    # on return:
    #   DOWNLOAD_URL contains the url for the requested download
    #   DOWNLOAD_URL_CACHE_ID contains an id that should be passed to
    #      the download_link function as the cache_file_name argument
    #   the return code is always 0
    #
    
    local ver="${1:-}"
    local ext="${2:-tar.bz2}"
    local url=""
    local url_cache_id=""

    if [ "${DOWNLOAD_NEXTCLOUD_FROM_GITHUB:-false}" == "true" ]; then
        # use Github REST API to obtain latest version and link. if
        # unsuccessful, fall back to using Nextcloud
        local github_ver=""
        if [ ! -z "$ver" ]; then
            github_ver="v${ver}"
            url="https://github.com/nextcloud/server/releases/download/${github_ver}/nextcloud-${ver}.${ext#.}"
            url_cache_id="nextcloud-${ver}.${ext#.}"
            
        elif [ -x "/usr/bin/jq" ]; then
            local latest="${REQUIRED_NC_FOR_FRESH_INSTALLS:-latest}"

            if [ "$latest" == "latest" ]; then
                github_ver=$(curl -s -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/nextcloud/server/tags 2>/dev/null | /usr/bin/jq  -r '.[].name' | grep -v -i -E '(RC|beta)' | head -1)  #eg: "v20.0.1"
            else
                local major=$(awk -F- '{print $2}' <<<"$latest")
                github_ver=$(curl -s -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/nextcloud/server/tags 2>/dev/null | /usr/bin/jq  -r '.[].name' | grep "^v$major\\." | grep -v -i -E '(RC|beta)' | head -1)  #eg: "v20.0.1"
            fi

            if [ $? -ne 0 ]; then
                say_verbose "Github API call failed! Using Nextcloud's server."
                # fall through and use nextcloud's download site
            else
                local github_plain_ver=$(awk -Fv '{print $2}' <<<"$github_ver")
                url="https://github.com/nextcloud/server/releases/download/$github_ver/nextcloud-${github_plain_ver}.${ext#.}"
                url_cache_id="nextcloud-${github_plain_ver}.${ext#.}"

            fi
        fi

        if [ ! -z "$url" ]; then
            # ensure the download exists - sometimes Github releases
            # only have sources and not a .bz2 file. In that case we
            # have to revert to using nextcloud's download server
            local http_status
            http_status="$(curl -s -L --head -w "%{http_code}" "$url" |tail -1)"
            local code=$?
            if [ $code -ne 0 ]; then
                say_verbose "Problem contacting Github to verify a download url ($code)"
                url=""
                
            elif [ "$http_status" != "403" -a "$http_status" != "200" ]; then
                say_verbose "Github doesn't have a download for $github_ver ($http_status)"
                url=""
                
            else
                # Github returns an html page with a redirect link
                # .. we have to extract the link
                local content
                content=$(download_link "$url" to-stdout no-cache)
                if [ $? -ne 0 ]; then
                    say_verbose "Unable to get Github download redir page"
                    url=""
                    
                else
                    #say_verbose "Got github redirect page content: $content"
                    content=$(python3 -c "import xml.etree.ElementTree as ET; tree=ET.fromstring(r'$content'); els=tree.findall('.//a'); print(els[0].attrib['href'])" 2>/dev/null)
                    if [ $? -ne 0 ]; then
                        say_verbose "Unable to parse Github redirect html"
                        url=""
                        
                    else
                        say_debug "Github redirected to $content"
                        url="$content"
                    fi
                fi
            fi
        fi
    fi
    

    if [ -z "$url" ]; then
        if [ -z "$ver" ]; then
            ver=${REQUIRED_NC_FOR_FRESH_INSTALLS:-latest}
        fi
        
        case "$ver" in
            latest )
                url="https://download.nextcloud.com/server/releases/latest.${ext#.}"
                url_cache_id="latest.${ext#.}"
                ;;

            *rc* )
                url="https://download.nextcloud.com/server/prereleases/nextcloud-${ver}.${ext#.}"
                url_cache_id="nextcloud-${ver}.${ext#.}"
                ;;
            
            * )
                url="https://download.nextcloud.com/server/releases/nextcloud-${ver}.${ext#.}"
                url_cache_id="nextcloud-${ver}.${ext#.}"
        esac
    fi

    DOWNLOAD_URL="$url"
    DOWNLOAD_URL_CACHE_ID="$url_cache_id"
    return 0
}



install_composer() {
    if [ ! -x /usr/local/bin/composer ]; then
        pushd /usr/local/bin >/dev/null
        curl -sS https://getcomposer.org/installer | hide_output php${PHP_VER}
        mv composer.phar composer
        popd >/dev/null
    else
        hide_output /usr/local/bin/composer selfupdate
    fi
}
