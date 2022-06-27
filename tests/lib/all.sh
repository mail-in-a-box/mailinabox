#
# source all lib scripts
#
#    eg source "tests/lib/all.sh"
#
# failure to load any script is fatal!

D=$(dirname "$BASH_SOURCE")

. "$D/color-output.sh" || exit 1
. "$D/locations.sh"    || exit 2
. "$D/misc.sh"         || exit 3
. "$D/rest.sh"         || exit 4
. "$D/system.sh"       || exit 5
. "$D/carddav.sh"      || exit 6

. "$D/populate.sh"     || exit 7
. "$D/installed-state.sh" || exit 8
. "$D/totp.sh"         || exit 9

