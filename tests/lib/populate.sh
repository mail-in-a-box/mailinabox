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
#   scripts: [ rest.sh, misc.sh ]
#

populate_miab_users() {
    local url="$1"
    local admin_email="${2:-$EMAIL_ADDR}"
    local admin_pass="${3:-$EMAIL_PW}"
    shift; shift; shift  # remaining arguments are users to add

    # each "user" argument is in the format "email:password"
    # if no password is given a "qa" password will be generated

    [ $# -eq 0 ] && return 0
    
    #
    # get the existing users
    #
    local current_users=() user
    if ! rest_urlencoded GET ${url%/}/admin/mail/users "$admin_email" "$admin_pass" --insecure 2>/dev/null; then
        echo "Unable to enumerate users: rc=$? err=$REST_ERROR" 1>&2
        return 1
    fi
    for user in $REST_OUTPUT; do
        current_users+=("$user")
    done

    #
    # add the new users
    #
    local pw="$(generate_qa_password)"
    
    for user; do
        local user_email="$(awk -F: '{print $1}' <<< "$user")"
        local user_pass="$(awk -F: '{print $2}' <<< "$user")"
        if array_contains "$user_email" "${current_users[@]}"; then
            echo "Not adding user $user_email: already exists"

        elif ! rest_urlencoded POST ${url%/}/admin/mail/users/add "$admin_email" "$admin_pass" --insecure -- "email=$user_email" "password=${user_pass:-$pw}" 2>/dev/null
        then
            echo "Unable to add user $user_email: rc=$? err=$REST_ERROR" 1>&2
            return 2
        else
            echo "Add: $user"
        fi
    done

    return 0
}



populate_miab_aliases() {
    local url="$1"
    local admin_email="${2:-$EMAIL_ADDR}"
    local admin_pass="${3:-$EMAIL_PW}"
    shift; shift; shift  # remaining arguments are aliases to add

    # each "alias" argument is in the format "email-alias > forward-to"

    [ $# -eq 0 ] && return 0
    
    #
    # get the existing aliases
    #
    local current_aliases=() alias
    if ! rest_urlencoded GET ${url%/}/admin/mail/aliases "$admin_email" "$admin_pass" --insecure 2>/dev/null; then
        echo "Unable to enumerate aliases: rc=$? err=$REST_ERROR" 1>&2
        return 1
    fi
    for alias in $REST_OUTPUT; do
        current_aliases+=("$alias")
    done

    #
    # add the new aliases
    #
    local aliasdef
    for aliasdef; do
        alias="$(awk -F'[> ]' '{print $1}' <<<"$aliasdef")"
        local forwards_to="$(sed 's/.*> *\(.*\)/\1/' <<<"$aliasdef")"
        if array_contains "$alias" "${current_aliases[@]}"; then
            echo "Not adding alias $aliasdef: already exists"
            
        elif ! rest_urlencoded POST ${url%/}/admin/mail/aliases/add "$admin_email" "$admin_pass" --insecure -- "address=$alias" "forwards_to=$forwards_to" 2>/dev/null
        then
            echo "Unable to add alias $alias: rc=$? err=$REST_ERROR" 1>&2
            return 2
        else
            echo "Add: $aliasdef"
        fi
    done

    return 0
}


