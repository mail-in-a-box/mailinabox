#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####

import logging
import re
import datetime
import traceback
import ipaddress
import threading
from logs.ReadLineHandler import ReadLineHandler
import logs.DateParser
from db.EventStore import EventStore
from util.DictQuery import DictQuery
from util.safe import (safe_int, safe_append, safe_del)

log = logging.getLogger(__name__)


class CommonHandler(ReadLineHandler):
    '''
    '''
    def __init__(self, state_cache_owner_id, record_store,
                 date_regexp = logs.DateParser.rsyslog_traditional_regexp,
                 date_parser_fn = logs.DateParser.rsyslog_traditional,
                 capture_enabled = True,
                 drop_disposition = None
    ):
        self.state_cache_owner_id = state_cache_owner_id
        
        ''' EventStore instance for persisting "records" '''
        self.record_store = record_store
        self.set_capture_enabled(capture_enabled)

        # our in-progress record queue is a simple list
        self.recs = self.get_cached_state(clear=True)
        self.current_inprogress_recs = len(self.recs)

        # records that have these dispositions will be dropped (not
        # recorded in the record store
        self.drop_disposition_lock = threading.Lock()
        self.drop_disposition = {
            'failed_login_attempt': False,
            'suspected_scanner': False,
            'reject': False
        }
        self.update_drop_disposition(drop_disposition)

        # regular expression that matches a syslog date (always anchored)
        self.date_regexp = date_regexp
        if date_regexp.startswith('^'):
            self.date_regexp = date_regexp[1:]

        # function that parses the syslog date
        self.date_parser_fn = date_parser_fn
        


    def get_inprogress_count(self):
        ''' thread-safe '''
        return self.current_inprogress_recs

    def update_inprogress_count(self):
        self.current_inprogress_recs = len(self.recs)
    
    def set_capture_enabled(self, capture_enabled):
        ''' thread-safe '''
        self.capture_enabled = capture_enabled

    def update_drop_disposition(self, drop_disposition):
        ''' thread-safe '''
        with self.drop_disposition_lock:
            self.drop_disposition.update(drop_disposition)

    def test_drop_disposition(self, disposition):
        with self.drop_disposition_lock:
            return self.drop_disposition.get(disposition, False)

    def datetime_as_str(self, d):
        # iso-8601 time friendly to sqlite3
        timestamp = d.isoformat(sep=' ', timespec='seconds')
        # strip the utc offset from the iso format (ie. remove "+00:00")
        idx = timestamp.find('+00:00')
        if idx>0:
            timestamp = timestamp[0:idx]
        return timestamp
        
    def parse_date(self, str):
        # we're expecting UTC times from date_parser()
        d = self.date_parser_fn(str)
        return self.datetime_as_str(d)
    
    def get_cached_state(self, clear=True):
        conn = None
        try:
            # obtain the cached records from the record store
            conn = self.record_store.connect()
            recs = self.record_store.read_rec(conn, 'state', {
                "owner_id": self.state_cache_owner_id,
                "clear": clear
            })
            log.info('read %s incomplete records from cache %s', len(recs), self.state_cache_owner_id)

            # eliminate stale records - "stale" should be longer than
            # the "give-up" time for postfix (4-5 days)
            stale = datetime.timedelta(days=7)
            cutoff = self.datetime_as_str(
                datetime.datetime.now(datetime.timezone.utc) - stale
            )            
            newlist = [ rec for rec in recs if rec['connect_time'] >= cutoff ]
            if len(newlist) < len(recs):
                log.warning('dropping %s stale incomplete records',
                            len(recs) - len(newlist))
            return newlist
        finally:
            if conn: self.record_store.close(conn)

    def save_state(self):
        log.info('saving state to cache %s: %s records', self.state_cache_owner_id, len(self.recs))
        self.record_store.store('state', {
            'owner_id': self.state_cache_owner_id,
            'state': self.recs
        })
    
    def end_of_callbacks(self, thread):
        '''overrides ReadLineHandler method

        save incomplete records so we can pick up where we left off

        '''
        self.update_inprogress_count()
        self.save_state()
