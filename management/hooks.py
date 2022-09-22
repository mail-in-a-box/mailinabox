# -*- indent-tabs-mode: t; tab-width: 4; python-indent-offset: 4; -*-
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####

import sys, os, stat, importlib
from threading import Lock
from utils import load_environment, load_env_vars_from_file
import logging

log = logging.getLogger(__name__)

#
# keep a list of hook handlers as a list of dictionaries. see
# update_hook_handlers() for the format
#
mutex = Lock()
handlers = [] 
mods_env = {}  # dict derived from /etc/mailinabox_mods.conf

def update_hook_handlers():
	global handlers, mods_env
	new_handlers= []
	for dir in sys.path:
		hooks_dir = os.path.join(dir, "management_hooks_d")
		if not os.path.isdir(hooks_dir):
			continue

		# gather a list of applicable hook handlers
		for item in os.listdir(hooks_dir):
			item_path = os.path.join(hooks_dir, item)
			mode = os.lstat(item_path).st_mode
			if item.endswith('.py') and stat.S_ISREG(mode):
				new_handlers.append({
					'sort_id': item,
					'path': "management_hooks_d.%s" % (item[0:-3]),
					'type': "py"
				})
				log.info('hook handler: %s', item_path)
	
	# handlers are sorted alphabetically by file name
	new_handlers = sorted(new_handlers, key=lambda path: path['sort_id'])
	log.info('%s hook handlers', len(new_handlers))

	# load /etc/mailinabox_mods.conf
	new_mods_env = load_environment()
	if os.path.isfile('/etc/mailinabox_mods.conf'):    
		load_env_vars_from_file(
			'/etc/mailinabox_mods.conf',
			strip_quotes=True,
			merge_env=new_mods_env
		)

	# update globals
	mutex.acquire()
	handlers = new_handlers
	mods_env = new_mods_env
	mutex.release()


def exec_hooks(hook_name, data):
	# `data` is a dictionary containing data from the hook caller, the
	# contents of which are specific to the type of hook. Handlers may
	# modify the dictionary to return updates to the caller.

	mutex.acquire()
	cur_handlers = handlers
	cur_mods_env = mods_env
	mutex.release()

	handled_count = 0
	
	for handler in cur_handlers:
		if handler['type'] == 'py':
			# load the python code and run the `do_hook` function
			module = importlib.import_module(handler['path'])
			do_hook = getattr(module, "do_hook")
			r = do_hook(hook_name, data, cur_mods_env)
			log.debug('hook handler %s(%s) returned: %s', handler['path'], hook_name, r)
			if r: handled_count = handled_count + 1

		else:
			log.error('Unknown hook handler type in %s: %s', handler['path'], handler['type'])

	return handled_count > 0

