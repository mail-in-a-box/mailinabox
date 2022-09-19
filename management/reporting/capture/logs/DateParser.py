#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####

import datetime
import pytz

rsyslog_traditional_regexp = '^(.{15})'

with open('/etc/timezone') as fp:
    timezone_id = fp.read().strip()


def rsyslog_traditional(str):
    # Handles the default timestamp in rsyslog
    # (RSYSLOG_TraditionalFileFormat)
    #
    # eg: "Dec 6 06:25:04"  (always 15 characters)
    #
    # the date string is in local time
    #
    d = datetime.datetime.strptime(str, '%b %d %H:%M:%S')

    # since the log date has no year, use the current year
    today = datetime.date.today()
    year = today.year
    if d.month == 12 and today.month == 1:
        year -= 1
    d = d.replace(year=year)

    # convert to UTC
    if timezone_id == 'Etc/UTC':
        return d
    local_tz = pytz.timezone(timezone_id)
    return local_tz.localize(d, is_dst=None).astimezone(pytz.utc)

    
