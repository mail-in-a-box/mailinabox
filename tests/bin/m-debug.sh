#!/bin/bash
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####


cd "$(dirname "$0")/../../management" || exit 1
systemctl stop mailinabox
source /usr/local/lib/mailinabox/env/bin/activate
export DEBUG=1
export FLASK_DEBUG=1
if ! systemctl is-active --quiet miabldap-capture; then
    export CAPTURE_STORAGE_ROOT=/mailinabox/management/reporting/capture/tests
fi
python3 --version
python3 ./daemon.py
