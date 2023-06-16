#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####


#
# This hooks management's dns_update and web_update for the
# remote-nextcloud setup mod.
#
# dns_update: When management/dns_update.py creates a new zone, this mod will
# change _caldavs._tcp and _carddavs._tcp to point to the remote
# nextcloud.
#
# web_update: When management/web_update.py creates a new nginx
# configuration file "/etc/nginx/conf.d/local.conf", this mod will
# ensure that .well-known/caldav and .well-known/carddav urls are
# redirected to the remote nextcloud.
#
# The hook is enabled by placing the file in directory
# LOCAL_MODS_DIR/managment_hooks_d.
#

import os
import logging

log = logging.getLogger(__name__)


def do_hook(hook_name, hook_data, mods_env):
    if 'NC_HOST' not in mods_env or mods_env['NC_HOST'].strip() == '':
        # not configured for a remote nextcloud
        log.debug('hook - not configured for a remote nextcloud')
        return False

    if hook_name == 'web_update':
        return do_hook_web_update(hook_name, hook_data, mods_env)

    elif hook_name == 'dns_update':
        return do_hook_dns_update(hook_name, hook_data, mods_env)

    else:
        log.debug('hook - ignoring hook %s', hook_name)
        return False


def do_hook_dns_update(hook_name, hook_data, mods_env):
    if hook_data['op'] != 'build_zone_end':
        log.debug('hook - ignoring hook op %s:%s', hook_name, hook_data['op'])
        return False
    changed = False
    records = hook_data['records']
    for idx in range(len(records)):
        # record format (name, record-type, record-value, "help-text" or False)
        record = records[idx]
        rname = record[0]
        rtype = record[1]
        if rtype=='SRV' and rname in ('_caldavs._tcp', '_carddavs._tcp'):
            newrec = list(record)
            newrec[2] = '10 10 %s %s.' % (
                mods_env['NC_PORT'],
                mods_env['NC_HOST']
            )
            records[idx] = tuple(newrec)
            changed = True
    return changed


def get_nc_url(mods_env):
    # return the remote nextcloud url - ensures no tailing /
    nc_url = "%s://%s:%s%s" % (
        mods_env['NC_PROTO'],
        mods_env['NC_HOST'],
        mods_env['NC_PORT'],
        mods_env['NC_PREFIX'][0:-1] if mods_env['NC_PREFIX'].endswith('/') else mods_env['NC_PREFIX']
    )
    return nc_url


def do_hook_web_update(hook_name, hook_data, mods_env):
    if hook_data['op'] != 'pre-save':
        log.debug('hook - ignoring hook op %s:%s', hook_name, hook_data['op'])
        return False
    
    nc_url = get_nc_url(mods_env)

    # find start and end of Nextcloud configuration section
    
    str = hook_data['nginx_conf']
    start = str.find('# Nextcloud configuration.')
    if start==-1:
        log.error("no Nextcloud configuration found in nginx conf")
        return False

    end = str.find('\n\t# ssl files ', start)    
    if end==0:
        log.error("couldn't determine end of Nextcloud configuration")
        return False
        
    # ensure we're not eliminating lines that are not nextcloud
    # related in the event that the conf/nginx-* templates change
    #
    # check that every main directive in the proposed section
    # (excluding block directives) should contains the text "cloud",
    # "carddav", or "caldav"
    
    for line in str[start:end].split('\n'):
        if line.startswith("\t\t"): continue
        line_stripped = line.strip()
        if line_stripped == "" or \
           line_stripped.startswith("#") or \
           line_stripped.startswith("}"):
            continue
        if line_stripped.find('cloud')==-1 and \
           line_stripped.find('carddav')==-1 and \
           line_stripped.find('caldav')==-1:
            log.error("nextcloud replacement block directive did not contain 'cloud', 'carddav' or 'caldav'. line=%s", line_stripped)
            return False

    
    # ok, do the replacement
    
    template = """# Nextcloud configuration.
	rewrite ^/cloud$ /cloud/ redirect;
	rewrite ^/cloud/(contacts|calendar|files)$ {nc_url}/index.php/apps/$1/ redirect;
	rewrite ^/cloud/(.*)$ {nc_url}/$1 redirect;
	
	rewrite ^/.well-known/carddav {nc_url}/remote.php/dav/ redirect;
	rewrite ^/.well-known/caldav {nc_url}/remote.php/dav/ redirect;
	rewrite ^/.well-known/webfinger {nc_url}/index.php/.well-known/webfinger redirect;
	rewrite ^/.well-known/nodeinfo {nc_url}/index.php/.well-known/nodeinfo redirect;
"""

    hook_data['nginx_conf'] = str[0:start] + template.format(nc_url=nc_url) + str[end:]
    return True
