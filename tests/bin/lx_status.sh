#!/bin/bash
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####


show() {
    local project="$1"
    local which=$2
    if [ -z "$which" -o "$which" = "instances" ]; then
        lxc --project "$project" list -c enfsd -f csv | sed "s/^/    /"
    fi

    if [ -z "$which" -o "$which" = "images" ]; then
        lxc --project "$project" image list -c lfsd -f csv | sed "s/^/    $project,/"
    fi
}

global="no"
if [ $# -gt 0 ]; then
    projects=( "$@" )
else
    global="yes"
    projects=( $(lxc project list -f csv | awk -F, '{print $1}' | sed 's/ .*$//') )
fi

if [ "$global" = "yes" ]; then
    echo "** projects"
    idx=0
    while [ $idx -lt ${#projects[*]} ]; do
        echo "    ${projects[$idx]}"
        let idx+=1
    done
else
    echo "Project: ${projects[*]}"
fi


echo "** images"
idx=0
while [ $idx -lt ${#projects[*]} ]; do
    project="${projects[$idx]}"
    let idx+=1
    show "$project" images $verbose
done

echo "** instances"
idx=0
while [ $idx -lt ${#projects[*]} ]; do
    project="${projects[$idx]}"
    let idx+=1
    show "$project" instances $verbose
done
