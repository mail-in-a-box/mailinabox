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
# this mod will enable roundcube debugging output. output goes
# /var/log/roundcubemail
#

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

# where webmail.sh installs roundcube
RCM_DIR=/usr/local/lib/roundcubemail
CONF=${1:-$RCM_DIR/config/config.inc.php}

php tools/editconf.php $CONF config \
    'log_driver' 'file' \
    'syslog_facility' 'constant("LOG_MAIL")' \
    'debug_level' '4' \
    'imap_debug' 'true' \
    'imap_log_session' 'true' \
    'sql_debug' 'true' \
    'smtp_debug' 'true' \
    'session_debug' 'true' \
    'log_logins' 'true' \
    'log_errors' 'true' \
    'per_user_logging' 'false' \
    'session_lifetime' '2'

