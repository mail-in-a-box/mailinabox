#!/bin/bash
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####


#
# Parallel provisioning for test vms
#

. "$(dirname "$0")/../bin/lx_functions.sh"
. "$(dirname "$0")/../lib/color-output.sh"
. "$(dirname "$0")/../lib/misc.sh"

boxlist=""    # the name of the boxlist or a path to the boxlist file
boxes=()      # the contents of the boxlist file
project="$(lx_guess_project_name)"

load_boxlist() {
    # sets global variable 'boxlist' and array 'boxes'
    boxlist="${1:-default}"
    local fn="$boxlist"
    if [ ! -f "$fn" ]; then
        fn="parallel-boxlist.$boxlist"
    fi
    if [ ! -f "$fn" ]; then
        echo "Could not load boxlist from '${boxlist}'! Failed to find '$fn'."
        exit 1
    fi
    boxes=( $(grep -v '^#' $fn) )
    if [ $? -ne 0 ]; then
        echo "Could not load boxlist from file '$fn'!"
        exit 1
    fi
}

# destroy running boxes
if [ "$1" = "-d" ]; then
    shift
    load_boxlist "$1"
    for inst in $(lx_output_inst_list "$project" "n" "csv"); do
        if array_contains $inst ${boxes[*]}; then
            echo lxc --project "$project" delete $inst --force
            lxc --project "$project" delete $inst --force
        fi
    done
    exit 0
elif [ "$1" = "-h" -o "$1" = "--help" ]; then
    echo "usage: $0 [-d] [boxlist]"
    echo "  -d    delete/destroy running boxes"
    echo "  boxlist   an file or named boxlist containing a list of instance names. defaults to 'default'"
    exit 0
fi

load_boxlist "$1"

# set total parallel vms to (#cores minus 1)
MAX_PROCS=$(cat /proc/cpuinfo | grep processor | wc -l)
let MAX_PROCS-=1
[ $MAX_PROCS -eq 0 ] && MAX_PROCS=1

OUTPUT_DIR=out
#rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

echo "MAX_PROCS=$MAX_PROCS"
echo "OUTPUT_DIR=$OUTPUT_DIR"

start_time="$(date +%s)"

# bring up in parallel
for inst in ${boxes[*]}; do
    outfile="$OUTPUT_DIR/$inst.out.txt"
    rm -f "$outfile"
    echo "Bringing up '$inst'. Output will be in: $outfile" 1>&2
    echo $inst
done | xargs -P $MAX_PROCS -I"INSTNAME" \
             sh -c '
cd "INSTNAME" &&
./provision.sh >'"../$OUTPUT_DIR/"'INSTNAME.out.txt 2>&1 &&
echo "EXITCODE: 0" >> '"../$OUTPUT_DIR/"'INSTNAME.out.txt ||
echo "EXITCODE: $?" >>'"../$OUTPUT_DIR/"'INSTNAME.out.txt
'

# output overall result"
H1 "Results"

rc=0
for inst in ${boxes[*]}; do
    file="$OUTPUT_DIR"/$inst.out.txt
    exitcode="$(tail "$file" | grep EXITCODE: | awk '{print $NF}')"
    echo -n "$inst: "
    if [ -z "$exitcode" ]; then
        danger "NO EXITCODE!"
        [ $rc -eq 0 ] && rc=2
    elif [ "$exitcode" == "0" ]; then
        elapsed="$(tail "$file" | grep ^Elapsed | awk -F: '{print $2}')"
        success "SUCCESS (${elapsed# })"
    else
        danger "FAILURE ($exitcode)"
        rc=1
    fi
done

# output elapsed time
end_time="$(date +%s)"
echo ""
echo "Elapsed time: $(elapsed_pretty $start_time $end_time)"

# exit
echo ""
echo "Guest VMs are running! Destroy them with:"
echo "   $0 -d $boxlist"
exit $rc
