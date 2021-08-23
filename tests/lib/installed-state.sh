#
# requires:
#    scripts: [ colored-output.sh, rest.sh ]
#
# these functions are meant for comparing upstream (non-LDAP)
# installations to a subsequent MiaB-LDAP upgrade
#


installed_state_capture() {
    # users and aliases
    # dns zone files
    # TOOD: tls certificates: expected CN's

    local state_dir="$1"
    local info="$state_dir/info.txt"

    H1 "Capture installed state to $state_dir"

    # nuke saved state, if any
    rm -rf "$state_dir"
    mkdir -p "$state_dir"

    # create info.json
    H2 "create info.txt"
    echo "STATE_VERSION=1" > "$info"
    echo "GIT_VERSION='$(git describe --abbrev=0)'" >>"$info"
    echo "GIT_ORIGIN='$(git remote -v | grep ^origin | grep 'fetch)$' | awk '{print $2}')'" >>"$info"
    echo "MIGRATION_VERSION=$(cat "$STORAGE_ROOT/mailinabox.version")" >>"$info"

    # record users
    H2 "record users"
    if ! rest_urlencoded GET "/admin/mail/users?format=json" "$EMAIL_ADDR" "$EMAIL_PW" --insecure 2>/dev/null
    then
        echo "Unable to get users: rc=$? err=$REST_ERROR" 1>&2
        return 1
    fi
    echo "$REST_OUTPUT" > "$state_dir/users.json"

    # record aliases
    H2 "record aliases"
    if ! rest_urlencoded GET "/admin/mail/aliases?format=json" "$EMAIL_ADDR" "$EMAIL_PW" --insecure 2>/dev/null
    then
        echo "Unable to get aliases: rc=$? err=$REST_ERROR" 1>&2
        return 2
    fi
    echo "$REST_OUTPUT" > "$state_dir/aliases.json"

    # record dns config
    H2 "record dns details"
    local file
    mkdir -p "$state_dir/zones"
    for file in /etc/nsd/zones/*.signed; do
        if ! cp "$file" "$state_dir/zones"
        then
            echo "Copy $file -> $state_dir/zones failed" 1>&2
            return 3
        fi
    done
    
    return 0
}



installed_state_compare() {
    local s1="$1"
    local s2="$2"
    
    local output
    local changed="false"

    H1 "COMPARE STATES: $(basename "$s1") VS $(basename "$2")"

    #
    # determine compare type id (incorporating repo, branch, version, etc)
    #
    local compare_type="all"
    
    source "$s2/info.txt"
    if [ -z "$GIT_ORIGIN" ] || grep "mailinabox-ldap.git" <<<"$GIT_ORIGIN" >/dev/null; then
        GIT_ORIGIN=""
        source "$s1/info.txt"
        if ! grep "mailinabox-ldap.git" <<<"$GIT_ORIGIN" >/dev/null; then
            compare_type="miab2miab-ldap"
        fi
    fi
    echo "Compare type: $compare_type"

    #
    # filter data for compare type
    #
    cp "$s1/users.json" "$s1/users-cmp.json" || changed="true"
    cp "$s1/aliases.json" "$s1/aliases-cmp.json" || changed="true"
    cp "$s2/users.json" "$s2/users-cmp.json" || changed="true"
    cp "$s2/aliases.json" "$s2/aliases-cmp.json" || changed="true"
    
    if [ "$compare_type" == "miab2miab-ldap" ]
    then
        # user display names is a feature added to MiaB-LDAP that is
        # not in MiaB
        grep -v '"display_name":' "$s2/users.json" > "$s2/users-cmp.json" || changed="true"

        # alias descriptions is a feature added to MiaB-LDAP that is
        # not in MiaB
        grep -v '"description":' "$s2/aliases.json" > "$s2/aliases-cmp.json" || changed="true"        
    fi    
    
    #
    # users
    #
    H2 "Users"
    output="$(diff "$s1/users-cmp.json" "$s2/users-cmp.json" 2>&1)"
    if [ $? -ne 0 ]; then
        changed="true"
        echo "USERS ARE DIFFERENT!"
        echo "$output"
    else
        echo "No change"
    fi

    #
    # aliases
    #
    H2 "Aliases"
    output="$(diff "$s1/aliases-cmp.json" "$s2/aliases-cmp.json" 2>&1)"
    if [ $? -ne 0 ]; then
        changed="true"
        echo "ALIASES ARE DIFFERENT!"
        echo "$output"
    else
        echo "No change"
    fi

    H2 "DNS - zones missing"
    local zone count=0
    for zone in $(cd "$s1/zones"; ls *.signed); do
        if [ ! -e "$s2/zones/$zone" ]; then
            echo "MISSING zone: $zone"
            changed="true"
            let count+=1
        fi
    done
    echo "$count missing"

    H2 "DNS - zones added"
    count=0
    for zone in $(cd "$s2/zones"; ls *.signed); do
        if [ ! -e "$s2/zones/$zone" ]; then
            echo "ADDED zone: $zone"
            changed="true"
            let count+=1
        fi
    done
    echo "$count added"

    H2 "DNS - zones changed"
    count=0
    for zone in $(cd "$s1/zones"; ls *.signed); do
        if [ -e "$s2/zones/$zone" ]; then
            # all the signatures change if we're using self-signed certs
            # ignore ttl changes
            local t1="/tmp/s1.$$.txt"
            local t2="/tmp/s2.$$.txt"
            awk '\
$4 == "RRSIG" || $4 == "NSEC3" { next; } \
$4 == "SOA" { print $1" "$3" "$4" "$5" "$6" "$8" "$10" "$12; next } \
{ for(i=1;i<=NF;i++) if (i!=2) printf("%s ",$i); print ""; }' \
                "$s1/zones/$zone" > "$t1"
            
            awk '\
$4 == "RRSIG" || $4 == "NSEC3" { next; } \
$4 == "SOA" { print $1" "$3" "$4" "$5" "$6" "$8" "$10" "$12; next } \
{ for(i=1;i<=NF;i++) if (i!=2) printf("%s ",$i); print ""; }' \
                "$s2/zones/$zone" > "$t2"
            
            output="$(diff "$t1" "$t2" 2>&1)"
            if [ $? -ne 0 ]; then
                echo "CHANGED zone: $zone"
                echo "$output"
                changed="true"
                let count+=1
            fi
        fi
    done
    echo "$count zone files had differences"

    if $changed; then
        return 1
    else
        return 0
    fi
}
