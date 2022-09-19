#!/usr/bin/env python3
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####

from logs.TailFile import TailFile
from mail.PostfixLogHandler import PostfixLogHandler
from mail.DovecotLogHandler import DovecotLogHandler
from logs.ReadPositionStoreInFile import ReadPositionStoreInFile
from db.SqliteConnFactory import SqliteConnFactory
from db.SqliteEventStore import SqliteEventStore
from db.Pruner import Pruner
from util.env import load_env_vars_from_file

import time
import logging, logging.handlers
import json
import re
import os
import sys
import signal

log = logging.getLogger(__name__)

if os.path.exists('/etc/mailinabox.conf'):
    env = load_env_vars_from_file('/etc/mailinabox.conf')
else:
    env = { 'STORAGE_ROOT': os.environ.get('STORAGE_ROOT', os.getcwd()) }

CAPTURE_STORAGE_ROOT = os.path.join(env['STORAGE_ROOT'], 'reporting')


# default configuration, if not specified or
# CAPTURE_STORAGE_ROOT/config.json does not exist
config_default = {
    'default_config': True,
    'capture': True,
    'prune_policy': {
        'frequency_min': 2400,
        'older_than_days': 30
    },
    'drop_disposition': {
        'failed_login_attempt': True,
        'suspected_scanner': False,
        'reject': True
    }
}

config_default_file = os.path.join(CAPTURE_STORAGE_ROOT, 'config.json')


# options
    
options = {
    'daemon': True,
    'log_level': logging.WARNING,
    'log_file': "/var/log/mail.log",
    'stop_at_eof': False,
    'pos_file': "/var/lib/mailinabox/capture-pos.json",
    'sqlite_file': os.path.join(CAPTURE_STORAGE_ROOT, 'capture.sqlite'),
    'working_dir': "/var/run/mailinabox",
    'config': config_default,
    '_config_file': False,  # absolute path if "config" was from a file
    '_runtime_config_file': "runtime_config.json" # relative to working_dir
}


def read_config_file(file, throw=False):
    try:
        with open(file) as fp:
            newconfig = json.loads(fp.read())
        newconfig['from'] = { 'type':'file', 'location':file }
        return newconfig
    except FileNotFoundError as e:
        if not throw:
            return False
        raise e

def write_config(tofile, config):
    d = os.path.dirname(tofile)
    if d and not os.path.exists(d):
        os.mkdir(d, mode=0o770)
    with open(tofile, "w") as fp:
        fp.write(json.dumps(config))

def usage():
    print('usage: %s [options]' % sys.argv[0])
    sys.exit(1)

def process_cmdline(options):
    argi = 1
    marg = 0
    while argi < len(sys.argv):
        arg = sys.argv[argi]
        have_next = ( argi+1 < len(sys.argv) )
        
        if arg=='-d':
            options['daemon'] = False
                
        elif arg=='-loglevel' and have_next:
            argi += 1
            arg = sys.argv[argi].lower()
            if arg=='info':
                options['log_level'] = logging.INFO
            elif arg=='warning':
                options['log_level'] = logging.WARNING
            elif arg=='debug':
                options['log_level'] = logging.DEBUG
            elif arg=='error':
                options['log_level'] = logging.ERROR
            else:
                sys.stderr.write('unknown log level "%s"\n' % sys.argv[argi])
                
        elif arg=='-config' and have_next:
            argi += 1
            arg = sys.argv[argi]
            try:
                if arg.startswith('{'):
                    options['config'] = json.loads(arg)
                else:
                    newconfig = read_config_file(arg, throw=True)
                    options['config'] = newconfig
                    options['_config_file'] = arg
            except Exception as e:
                if options['daemon']: log.exception(e)
                raise e

        elif arg=='-logfile' and have_next:
            argi+=1
            options['log_file'] = sys.argv[argi]

        elif arg=='-stopateof':
            argi+=1
            options['stop_at_eof'] = True
            
        elif arg=='-posfile' and have_next:
            argi+=1
            options['pos_file'] = sys.argv[argi]
            
        elif arg=='-sqlitefile' and have_next:
            argi+=1
            options['sqlite_file'] = sys.argv[argi]            

        elif arg.startswith('-'):
            usage()

        else:
            if marg==0:
                options['log_file'] = arg
            elif marg==1:
                options['pos_file'] = arg
            elif marg==2:
                options['sqlite_file'] = arg
            else:
                usage()
            marg += 1
        argi += 1


def set_working_dir(working_dir):
    try:
        if not os.path.exists(working_dir):
            os.mkdir(working_dir, mode=0o770)
        os.chdir(working_dir)
    except Exception as e:
        log.exception(e)
        raise e

def close_stdio():
    sys.stdout.close()
    sys.stderr.close()
    sys.stdin.close()

    
# if config.json exists in the default location start with that
# instead of `config_default`. config can still be changed with the
# command line argument "-config"

newconfig = read_config_file(config_default_file, throw=False)
if newconfig:
    options['config'] = newconfig
    options['_config_file'] = config_default_file
    
# process command line
process_cmdline(options)


# init logging & set working directory
if options['daemon']:
    logging.basicConfig(
        level = options['log_level'],
        handlers= [
            logging.handlers.SysLogHandler(address='/dev/log')
        ],
        format = 'miabldap/capture %(message)s'
    )
    log.warning('MIAB-LDAP capture/SEM daemon starting: wd=%s; log_file=%s; pos_file=%s; db=%s',
                options['working_dir'],
                options['log_file'],
                options['pos_file'],
                options['sqlite_file']
    )
    close_stdio()
    set_working_dir(options['working_dir'])
    
else:
    logging.basicConfig(level=options['log_level'])
    log.info('starting: log_file=%s; pos_file=%s; db=%s',
             options['log_file'],
             options['pos_file'],
             options['sqlite_file']
    )


# save runtime config
write_config(options['_runtime_config_file'], options['config'])


# start modules
log.info('config: %s', options['config'])
try:
    db_conn_factory = SqliteConnFactory(
        options['sqlite_file']
    )
    event_store = SqliteEventStore(
        db_conn_factory
    )
    position_store = ReadPositionStoreInFile(
        options['pos_file']
    )
    mail_tail = TailFile(
        options['log_file'],
        position_store,
        options['stop_at_eof']
    )
    postfix_log_handler = PostfixLogHandler(
        event_store,
        capture_enabled = options['config'].get('capture',True),
        drop_disposition = options['config'].get('drop_disposition')
    )
    mail_tail.add_handler(postfix_log_handler)
    dovecot_log_handler = DovecotLogHandler(
        event_store,
        capture_enabled = options['config'].get('capture',True),
        drop_disposition = options['config'].get('drop_disposition')
    )
    mail_tail.add_handler(dovecot_log_handler)
    pruner = Pruner(
        db_conn_factory,
        policy=options['config']['prune_policy']
    )
    pruner.add_prunable(event_store)
    
except Exception as e:
    if options['daemon']: log.exception(e)
    raise e


# termination handler for graceful shutdowns
def terminate(sig, stack):
    if sig == signal.SIGTERM:
        log.warning("shutting down due to SIGTERM")
    log.debug("stopping mail_tail")
    mail_tail.stop()

# reload settings handler
def reload(sig, stack):
    # if the default config (`config_default`) is in use, check to see
    # if a default config.json (`config_default_file`) now exists, and
    # if so, use that
    if options['config'].get('default_config', False) and os.path.exists(config_default_file):
        options['config']['default_config'] = False
        options['_config_file'] = config_default_file

    log.info('%s mta records are in-progress',
             postfix_log_handler.get_inprogress_count())
    log.info('%s imap records are in-progress',
             dovecot_log_handler.get_inprogress_count())

    if options['_config_file']:
        log.info('reloading %s', options['_config_file'])
        try:
            newconfig = read_config_file(options['_config_file'], throw=True)
            pruner.set_policy(
                newconfig['prune_policy']
            )
            postfix_log_handler.set_capture_enabled(
                newconfig.get('capture', True)
            )
            postfix_log_handler.update_drop_disposition(
                newconfig.get('drop_disposition', {})
            )
            dovecot_log_handler.set_capture_enabled(
                newconfig.get('capture', True)
            )
            dovecot_log_handler.update_drop_disposition(
                newconfig.get('drop_disposition', {})
            )
            write_config(options['_runtime_config_file'], newconfig)
        except Exception as e:
            if options['daemon']:
                log.exception(e)
            else:
                raise e

signal.signal(signal.SIGTERM, terminate)
signal.signal(signal.SIGINT, terminate)
signal.signal(signal.SIGHUP, reload)


# monitor and capture
mail_tail.start()
mail_tail.join()

# gracefully close other threads
log.debug("stopping pruner")
pruner.stop()
log.debug("stopping position_store")
position_store.stop()
log.debug("stopping event_store")
event_store.stop()
try:
    os.remove(options['_runtime_config_file'])
except Exception:
    pass
log.info("stopped")
