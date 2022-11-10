#!/bin/bash
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####


# use this to run a browser test from the command line

mydir=$(dirname "$0")
export PYTHONPATH=$(realpath "$mydir/../lib/python"):$PYTHONPATH
export BROWSER_TESTS_VERBOSITY=3

python3 "$@"
