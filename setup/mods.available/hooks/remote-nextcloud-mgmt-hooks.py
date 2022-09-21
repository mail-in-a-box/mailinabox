
#
# This is a web_update management hook for the remote-nextcloud setup
# mod.
#
# When management/web_update.py creates a new nginx configuration file
# "local.conf", this mod will ensure that .well-known/caldav and
# .well-known/carddav urls are redirected to the remote nextcloud.
#
# The hook is enabled by placing the file in directory
# LOCAL_MODS_DIR/managment_hooks_d.
#

import os
import logging

log = logging.getLogger(__name__)


def do_hook(hook_name, hook_data, mods_env):
    if hook_name != 'web_update':
        # we only care about hooking web_update
        log.debug('hook - ignoring %s' % hook_name)
        return False

    if 'NC_HOST' not in mods_env or mods_env['NC_HOST'].strip() == '':
        # not configured for a remote nextcloud
        log.debug('hook - not configured for a remote nextcloud')
        return False
    
    # get the remote nextcloud url and ensure no tailing /
    nc_url = "%s://%s:%s%s" % (
        mods_env['NC_PROTO'],
        mods_env['NC_HOST'],
        mods_env['NC_PORT'],
        mods_env['NC_PREFIX'][0:-1] if mods_env['NC_PREFIX'].endswith('/') else mods_env['NC_PREFIX']
    )

    #
    # modify nginx_conf
    #
    def do_replace(find_str, replace_with):
        if hook_data['nginx_conf'].find(find_str) == -1:
            log.warning('remote-nextcloud hook: string "%s" not found in proposed nginx_conf' % (find_str))
            return False
        hook_data['nginx_conf'] = hook_data['nginx_conf'].replace(
            find_str,
            replace_with
        )
        return True
            
    # 1. change the .well-known/(caldav|carddav) redirects
    do_replace(
        '/cloud/remote.php/dav/',
        '%s/remote.php/dav/' % nc_url
    )
    
    # 2. redirect /cloud to the remote nextcloud
    do_replace(
        'rewrite ^/cloud/$ /cloud/index.php;',
        'rewrite ^/cloud/(.*)$ %s/$1 redirect;' % nc_url
    )

