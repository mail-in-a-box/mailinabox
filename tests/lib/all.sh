#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####

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
. "$D/webdav.sh"       || exit 7

. "$D/populate.sh"     || exit 8
. "$D/installed-state.sh" || exit 9
. "$D/totp.sh"         || exit 10

