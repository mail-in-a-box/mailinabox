#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####

def safe_int(str, default_value=0):
    try:
        return int(str)
    except ValueError:
        return default_value

def safe_append(d, key, value):
    if key not in d:
        d[key] = [ value ]
    else:
        d[key].append(value)
    return d

def safe_del(d, key):
    if key in d:
        del d[key]
    return d

