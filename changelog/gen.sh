#!/bin/bash

#
# save a list of commits as markdown for a given tag or for a tag
# determined automatically from bootstrap.sh and the current tag list
#
# this should be run from master, right before pushing a new release
# tag
#

scriptdir=$(dirname "$0")
miabdir="$scriptdir/.."

branch=$(git branch --show-current)
if [ $? -ne 0 ]; then
    exit 1
fi
echo "Branch: $branch"

tag_from_bootstrap() {
    TAG=$(grep TAG= "$miabdir/setup/bootstrap.sh" | head -1 | awk -F= '{print $2}')
    if [ $? -ne 0 -o -z "$TAG" ]; then
        echo "Could not determine code version from bootstrap.sh !!!" 1>&2
        return 1
    fi
}

tag_from_git() {
    local code="0"
    case "$1" in
        # the argument is a negative number (or blank). return the nth
        # tag from bottom of the list given by `git tag`
        -* | "" )
        TAG=$(git tag | tail ${1:--1} | head -1)
        code=$?
        ;;

        # else, return the tag prior to the tag given
        * )
        TAG=$(git tag | grep -B1 -F "$1" | head -1)
        code=$?
    esac

    if [ $code -ne 0 -o -z "$TAG" ]; then
        echo "Could not determine code version from git tag !!! arg=${1} code=$code" 1>&2
        return 1
    fi
}

tag_exists() {
    local count
    count=$(git tag | grep -c -xF "$1")
    [ $count -eq 1 ] && return 0
    [ $count -eq 0 ] && return 1
    # should never happen...
    echo "Problem: tag '$1' matches more than one line in git tag. Exiting."
    exit 1
}

create_changelog() {
    local from_ref="$1"
    local to_ref="$2"
    echo "Running: git log $from_ref..$to_ref" 1>&2
    echo "| COMMIT | DATE | AUTHOR | TITLE |"
    echo "| ------ | ---- | ------ | ----- |"
    git log --no-merges --format="| [%h](https://github.com/downtownallday/mailinabox-ldap/commit/%H) | %cs | _%an_ | %s |" $from_ref..$to_ref
}


#
# if a tag was given on the command line:
#     output commits between
#       a. tag prior to tag given, and
#       b. tag given

if [ ! -z "$1" ]; then
    to_ref="$1"
    tag_from_git "$1" || exit 1
    from_ref="$TAG"
    echo "Creating: $scriptdir/$to_ref.md"
    cat > "$scriptdir/$to_ref.md" <<EOF
## Commits for $to_ref
EOF
    create_changelog "$from_ref" "$to_ref" >> "$scriptdir/$to_ref.md" || exit 1

else
    tag_from_bootstrap || exit 1
    bs_tag="$TAG"
    echo -n "Bootstrap.sh tag $bs_tag: "
    if tag_exists "$bs_tag"; then
        echo "already exists"
        of="$scriptdir/$branch.md"
        if [ "$branch" != "master" ]; then
            from_ref="master"
            to_ref="$branch"
            title="Unmerged commits from feature branch _${branch}_"
        else
            tag_from_git || exit 1
            from_ref="$TAG"
            to_ref="HEAD"
            title="Commits on $branch since $from_ref"
        fi
        
    else
        echo "is new"
        if [ "$branch" != "master" ]; then
            of="$scriptdir/$branch.md"
            from_ref="master"
            to_ref="$branch"
            title="Unmerged commits from feature branch _${branch}_"
        else
            of="$scriptdir/$bs_tag"
            tag_from_git || exit 1
            from_ref="$TAG"
            to_ref="HEAD"
            title="Commits for $bs_tag"
        fi
    fi

    echo "Creating: $of"
    cat > "$of" <<EOF
## $title
EOF
    create_changelog "$from_ref" "$to_ref" >> "$of" || exit 1

fi

