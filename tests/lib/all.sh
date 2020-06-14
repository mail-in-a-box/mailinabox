#
# source all lib scripts
#
# from your script, supply the path to this directory as the first argument
#
#    eg source "tests/lib/all.sh" "tests/lib"
#
# failure to load any script is fatal!

. "$1/color-output.sh" || exit 1
. "$1/locations.sh"    || exit 2
. "$1/misc.sh"         || exit 3
. "$1/rest.sh"         || exit 4
. "$1/system.sh"       || exit 5


