#!/bin/bash

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
