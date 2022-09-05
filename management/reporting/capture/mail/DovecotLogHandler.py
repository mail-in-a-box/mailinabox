import logging
import re
import datetime
import ipaddress
import threading
from logs.ReadLineHandler import ReadLineHandler
import logs.DateParser
from db.EventStore import EventStore
from util.DictQuery import DictQuery
from util.safe import (safe_int, safe_append, safe_del)
from .CommonHandler import CommonHandler

log = logging.getLogger(__name__)


STATE_CACHE_OWNER_ID = 2

class DovecotLogHandler(CommonHandler):
    '''
    '''
    def __init__(self, record_store,
                 date_regexp = logs.DateParser.rsyslog_traditional_regexp,
                 date_parser_fn = logs.DateParser.rsyslog_traditional,
                 capture_enabled = True,
                 drop_disposition = None
    ):
        super(DovecotLogHandler, self).__init__(
            STATE_CACHE_OWNER_ID,
            record_store,
            date_regexp,
            date_parser_fn,
            capture_enabled,
            drop_disposition
        )
                

        # A "record" is composed by parsing all the syslog output from
        # the activity generated by dovecot (imap, pop3) from a single
        # remote connection. Once a full history of the connection,
        # the record is written to the record_store.
        #
        # `recs` is an array holding incomplete, in-progress
        # "records". This array has the following format:
        #
        # (For convenience, it's easier to refer to the table column
        # names found in SqliteEventStore for the dict member names that
        # are used here since they're all visible in one place.)
        #
        # [{
        #   ... fields of the imap_connection table ...
        # }]
        #
        # IMPORTANT:
        #
        # No methods in this class are safe to call by any thread
        # other than the caller of handle(), unless marked as
        # thread-safe.
        #

        # maximum size of the in-progress record queue (should be the
        # same or greater than the maximum simultaneous dovecot/imap
        # connections allowed, which is dovecot settings
        # `process_limit` times `client_limit`, which defaults to 100
        # * 1000)
        self.max_inprogress_recs = 100 * 1000

        
        # 1a. imap-login: Info: Login: user=<keith@just1w.com>, method=PLAIN, rip=146.168.130.9, lip=192.155.92.185, mpid=5866, TLS, session=<IF3v7ze27dKSqIIJ>
        #    1=date
        #    2=service ("imap-login" or "pop3-login")
        #    3=sasl_username ("user@domain.com")
        #    4=sasl_method ("PLAIN")
        #    5=remote_ip ("146.168.130.9")
        #    6=local_ip
        #    7=service_tid ("5866")
        #    8=connection_security ("TLS")
        self.re_connect_success = re.compile('^' + self.date_regexp + ' (imap-login|pop3-login): Info: Login: user=<([^>]*)>, method=([^,]*), rip=([^,]+), lip=([^,]+), mpid=([^,]+), ([^,]+)')

        # 1a. imap-login: Info: Disconnected (auth failed, 1 attempts in 4 secs): user=<fernando@athigo.com>, method=PLAIN, rip=152.67.63.172, lip=192.155.92.185, TLS: Disconnected, session=<rho/Rjq2EqSYQz+s>
        #    1=date
        #    2=service ("imap-login" or "pop3-login")
        #    3=dissconnect_reason
        #    4=remote_auth_attempts
        #    5=sasl_username
        #    6=sasl_method
        #    7=remote_ip
        #    8=local_ip
        #    9=connection_security
        self.re_connect_fail_1 = re.compile('^' + self.date_regexp + ' (imap-login|pop3-login): Info: (?:Disconnected|Aborted login) \(([^,]+), (\d+) attempts[^\)]*\): user=<([^>]*)>, method=([^,]+), rip=([^,]+), lip=([^,]+), ([^,]+)')
        
        # 2a. pop3-login: Info: Disconnected (no auth attempts in 2 secs): user=<>, rip=196.52.43.85, lip=192.155.92.185, TLS handshaking: SSL_accept() failed: error:14209102:SSL routines:tls_early_post_process_client_hello:unsupported protocol, session=<ehaSaDm2x9vENCtV>
        # 2b. imap-login: Info: Disconnected (no auth attempts in 2 secs): user=<>, rip=92.118.160.61, lip=192.155.92.185, TLS handshaking: SSL_accept() failed: error:14209102:SSL routines:tls_early_post_process_client_hello:unsupported protocol, session=<cvmKhjq2qtJcdqA9>
        #    1=date
        #    2=service ("imap-login" or "pop3-login")
        #    3=disconnect_reason
        #    4=sasl_username ("")
        #    5=remote_ip ("146.168.130.9")
        #    6=local_ip
        #    7=connection_security
        self.re_connect_fail_2 = re.compile('^' + self.date_regexp + ' (imap-login|pop3-login): Info: (?:Disconnected|Aborted login) \(([^\)]*)\): user=<([^>]*)>, rip=([^,]+), lip=([^,]+), ([^,]+)')

        #3a. imap-login: Info: Disconnected (client didn't finish SASL auth, waited 0 secs): user=<>, method=PLAIN, rip=107.107.63.148, lip=192.155.92.185, TLS: SSL_read() syscall failed: Connection reset by peer, session=<rmBsIP21Zsdraz+U>
        #    1=date
        #    2=service ("imap-login" or "pop3-login")
        #    3=disconnect_reason
        #    4=sasl_username ("")
        #    5=sasl_method
        #    6=remote_ip ("146.168.130.9")
        #    7=local_ip
        #    8=connection_security
        self.re_connect_fail_3 = re.compile('^' + self.date_regexp + ' (imap-login|pop3-login): Info: (?:Disconnected|Aborted login) \(([^\)]*)\): user=<([^>]*)>, method=([^,]+), rip=([^,]+), lip=([^,]+), ([^,]+)')

        # 4a. pop3-login: Info: Disconnected: Too many bad commands (no auth attempts in 0 secs): user=<>, rip=83.97.20.35, lip=192.155.92.185, TLS, session=<BH8JRCi2nJ5TYRQj>
        #    1=date
        #    2=service ("imap-login" or "pop3-login")
        #    3=disconnect_reason
        #    4=sasl_username ("")
        #    5=remote_ip ("146.168.130.9")
        #    6=local_ip
        #    7=connection_security
        self.re_connect_fail_4 = re.compile('^' + self.date_regexp + ' (imap-login|pop3-login): Info: Disconnected: ([^\(]+) \(no auth attempts [^\)]+\): user=<([^>]*)>, rip=([^,]+), lip=([^,]+), ([^,]+)')

        # 5a. imap-login: Info: Disconnected: Too many bad commands (auth failed, 1 attempts in 4 secs): user=<fernando@athigo.com>, method=PLAIN, rip=152.67.63.172, lip=192.155.92.185, TLS: Disconnected, session=<rho/Rjq2EqSYQz+s>
        #    1=date
        #    2=service ("imap-login" or "pop3-login")
        #    3=disconnect_reason
        #    4=remote_auth_attempts
        #    5=sasl_username
        #    6=sasl_method
        #    7=remote_ip
        #    8=local_ip
        #    9=connection_security
        self.re_connect_fail_5 = re.compile('^' + self.date_regexp + ' (imap-login|pop3-login): Info: (?:Disconnected|Aborted login): ([^\(]+) \(auth failed, (\d+) attempts [^\)]+\): user=<([^>]*)>, method=([^,]+), rip=([^,]+), lip=([^,]+), ([^,]+)')


        # 1a. imap(jzw@just1w.com): Info: Logged out in=29 out=496
        #
        # 1b. imap(jzw@just1w.com): Info: Connection closed (IDLE running for 0.001 + waiting input for 5.949 secs, 2 B in + 10 B out, state=wait-input) in=477 out=6171
        # 1c. imap(jzw@just1w.com): Info: Connection closed (UID STORE finished 0.225 secs ago) in=8099 out=21714

        # 1d. imap(jzw@just1w.com): Info: Connection closed (LIST finished 115.637 secs ago) in=629 out=11130
        #
        # 1e. imap(jzw@just1w.com): Info: Connection closed (APPEND finished 0.606 secs ago) in=11792 out=10697
        #
        # 1f. imap(jzw@just1w.com): Info: Disconnected for inactivity in=1518 out=2962
        #
        # 1g. imap(keith@just1w.com): Info: Server shutting down. in=720 out=7287
        #    1=date
        #    2=service ("imap" or "pop3")
        #    3=sasl_username
        #    4=disconnect_reason ("Disconnected for inactivity")
        #    5=in_bytes
        #    6=out_bytes
        self.re_disconnect = re.compile('^' + self.date_regexp + ' (imap|pop3)\(([^\)]*)\): Info: ((?:Logged out|Connection closed|Disconnected|Server shutting down).*) in=(\d+) out=(\d+)')
        

        
    def add_new_connection(self, imap_conn):
        ''' queue an imap_connection record '''
        threshold = self.max_inprogress_recs + ( len(self.recs) * 0.05 )
        if len(self.recs) > threshold:
            backoff = len(self.recs) - self.max_inprogress_recs + int( self.max_inprogress_recs * 0.10 )
            log.warning('dropping %s old imap records', backoff)
            self.recs = self.recs[min(len(self.recs),backoff):]
            
        self.recs.append(imap_conn)
        return imap_conn
    
    def remove_connection(self, imap_conn):
        ''' remove a imap_connection record from queue '''
        self.recs.remove(imap_conn)

    def find_by(self, imap_conn_q, debug=False):
        '''find records using field-matching queries

        return a list of imap_conn matching query `imap_conn_q`
        '''
        
        if debug:
            log.debug('imap_accept_q: %s', imap_accept_q)
            
        # find all candidate recs with matching imap_conn_q, ordered by most
        # recent last
        candidates = DictQuery.find(self.recs, imap_conn_q, reverse=False)
        if len(candidates)==0:
            if debug: log.debug('no candidates')
            return []
        
        elif not candidates[0]['exact']:
            # there were no exact matches. apply autosets to the best
            # match requiring the fewest number of autosets (index 0)
            if debug: log.debug('no exact candidates')
            DictQuery.autoset(candidates[0])
            candidates[0]['exact'] = True
            candidates = [ candidates[0] ]
            
        else:
            # there is at least one exact match - remove all non-exact
            # candidates
            candidates = [
                candidate for candidate in candidates if candidate['exact']
            ]
            
        return [ candidate['item'] for candidate in candidates ]


    def find_first(self, *args, **kwargs):
        '''find the "best" result and return it - find_by() returns the list
        ordered, with the first being the "best"

        '''
        r = self.find_by(*args, **kwargs)
        if len(r)==0:
            return None
        return r[0]

    def match_connect_success(self, line):
        #    1=date
        #    2=service ("imap-login" or "pop3-login")
        #    3=sasl_username ("user@domain.com")
        #    4=sasl_method ("PLAIN")
        #    5=remote_ip ("146.168.130.9")
        #    6=local_ip
        #    7=service_tid ("5866")
        #    8=connection_security ("TLS")
        m = self.re_connect_success.search(line)
        if m:
            imap_conn = {
                "connect_time": self.parse_date(m.group(1)), # "YYYY-MM-DD HH:MM:SS"
                "service": m.group(2),
                "sasl_username": m.group(3),
                "sasl_method": m.group(4),
                "remote_host": "unknown",
                "remote_ip": m.group(5),
                "service_tid": m.group(7),
                "connection_security": m.group(8),
                "remote_auth_success": 1,
                "remote_auth_attempts": 1
            }
            self.add_new_connection(imap_conn)
            return { 'imap_conn': imap_conn }

    def match_connect_fail(self, line):
        m = self.re_connect_fail_1.search(line)
        if m:
            # 1a. imap-login: Info: Disconnected (auth failed, 1 attempts in 4 secs): user=<fernando@athigo.com>, method=PLAIN, rip=152.67.63.172, lip=192.155.92.185, TLS: Disconnected, session=<rho/Rjq2EqSYQz+s>
            #    1=date
            #    2=service ("imap-login" or "pop3-login")
            #    3=dissconnect_reason
            #    4=remote_auth_attempts
            #    5=sasl_username
            #    6=sasl_method
            #    7=remote_ip
            #    8=local_ip
            #    9=connection_security
            d = self.parse_date(m.group(1))  # "YYYY-MM-DD HH:MM:SS"
            imap_conn = {
                "connect_time": d,
                "disconnect_time": d,
                "disconnect_reason": m.group(3),
                "service": m.group(2),
                "sasl_username": m.group(5),
                "sasl_method": m.group(6),
                "remote_host": "unknown",
                "remote_ip": m.group(7),
                "connection_security": m.group(9),
                "remote_auth_success": 0,
                "remote_auth_attempts": int(m.group(4))
            }
            self.add_new_connection(imap_conn)
            return { 'imap_conn': imap_conn }

        m = self.re_connect_fail_2.search(line)
        if m:
            # 2a. pop3-login: Info: Disconnected (no auth attempts in 2 secs): user=<>, rip=196.52.43.85, lip=192.155.92.185, TLS handshaking: SSL_accept() failed: error:14209102:SSL routines:tls_early_post_process_client_hello:unsupported protocol, session=<ehaSaDm2x9vENCtV>
            #    1=date
            #    2=service ("imap-login" or "pop3-login")
            #    3=disconnect_reason
            #    4=sasl_username ("")
            #    5=remote_ip ("146.168.130.9")
            #    6=local_ip
            #    7=connection_security
            d = self.parse_date(m.group(1))  # "YYYY-MM-DD HH:MM:SS"
            imap_conn = {
                "connect_time": d,
                "disconnect_time": d,
                "disconnect_reason": m.group(3),
                "service": m.group(2),
                "sasl_username": m.group(4),
                "remote_host": "unknown",
                "remote_ip": m.group(5),
                "connection_security": m.group(7),
                "remote_auth_success": 0,
                "remote_auth_attempts": 0
            }
            self.add_new_connection(imap_conn)
            return { 'imap_conn': imap_conn }

        m = self.re_connect_fail_3.search(line)
        if m:
            #3a. imap-login: Info: Disconnected (client didn't finish SASL auth, waited 0 secs): user=<>, method=PLAIN, rip=107.107.63.148, lip=192.155.92.185, TLS: SSL_read() syscall failed: Connection reset by peer, session=<rmBsIP21Zsdraz+U>
            #    1=date
            #    2=service ("imap-login" or "pop3-login")
            #    3=disconnect_reason
            #    4=sasl_username ("")
            #    5=sasl_method
            #    6=remote_ip ("146.168.130.9")
            #    7=local_ip
            #    8=connection_security
            d = self.parse_date(m.group(1))  # "YYYY-MM-DD HH:MM:SS"
            imap_conn = {
                "connect_time": d,
                "disconnect_time": d,
                "disconnect_reason": m.group(3),
                "service": m.group(2),
                "sasl_username": m.group(4),
                "sasl_method": m.group(5),
                "remote_host": "unknown",
                "remote_ip": m.group(6),
                "connection_security": m.group(8),
                "remote_auth_success": 0,
                "remote_auth_attempts": 0
            }
            self.add_new_connection(imap_conn)
            return { 'imap_conn': imap_conn }

        m = self.re_connect_fail_4.search(line)
        if m:
            # 4a. pop3-login: Info: Disconnected: Too many bad commands (no auth attempts in 0 secs): user=<>, rip=83.97.20.35, lip=192.155.92.185, TLS, session=<BH8JRCi2nJ5TYRQj>
            #    1=date
            #    2=service ("imap-login" or "pop3-login")
            #    3=disconnect_reason
            #    4=sasl_username ("")
            #    5=remote_ip ("146.168.130.9")
            #    6=local_ip
            #    7=connection_security
            d = self.parse_date(m.group(1))  # "YYYY-MM-DD HH:MM:SS"
            imap_conn = {
                "connect_time": d,
                "disconnect_time": d,
                "disconnect_reason": m.group(3),
                "service": m.group(2),
                "sasl_username": m.group(4),
                "remote_host": "unknown",
                "remote_ip": m.group(5),
                "connection_security": m.group(6),
                "remote_auth_success": 0,
                "remote_auth_attempts": 0
            }
            self.add_new_connection(imap_conn)
            return { 'imap_conn': imap_conn }

        m = self.re_connect_fail_5.search(line)
        if m:
            # 5a. imap-login: Info: Disconnected: Too many bad commands (auth failed, 1 attempts in 4 secs): user=<fernando@athigo.com>, method=PLAIN, rip=152.67.63.172, lip=192.155.92.185, TLS: Disconnected, session=<rho/Rjq2EqSYQz+s>
            #    1=date
            #    2=service ("imap-login" or "pop3-login")
            #    3=disconnect_reason
            #    4=remote_auth_attempts
            #    5=sasl_username
            #    6=sasl_method
            #    7=remote_ip
            #    8=local_ip
            #    9=connection_security
            d = self.parse_date(m.group(1))  # "YYYY-MM-DD HH:MM:SS"
            imap_conn = {
                "connect_time": d,
                "disconnect_time": d,
                "disconnect_reason": m.group(3),
                "service": m.group(2),
                "sasl_username": m.group(5),
                "sasl_method": m.group(6),
                "remote_host": "unknown",
                "remote_ip": m.group(7),
                "connection_security": m.group(9),
                "remote_auth_success": 0,
                "remote_auth_attempts": int(m.group(4))
            }
            self.add_new_connection(imap_conn)
            return { 'imap_conn': imap_conn }


    def match_disconnect(self, line):
        #    1=date
        #    2=service ("imap" or "pop3")
        #    3=sasl_username
        #    4=disconnect_reason ("Logged out")
        #    5=in_bytes
        #    6=out_bytes
        #
        # NOTE: there is no way to match up the disconnect with the
        # actual connection because Dovecot does not log a service_tid
        # or an ip address or anything else that could be used to
        # match the two up. We'll just assign the disconnect to the
        # oldest connection for the user.
        m = self.re_disconnect.search(line)
        if m:
            v = {
                "service": m.group(2),
                "disconnect_time": self.parse_date(m.group(1)),
                "disconnect_reason": m.group(4),
                "in_bytes": int(m.group(5)),
                "out_bytes": int(m.group(6))
            }
            imap_conn_q = [
                { 'key':'service', 'value':m.group(2) + '-login' },
                { 'key':'sasl_username', 'value':m.group(3),
                  'ignorecase': True }
            ]
            log.debug(imap_conn_q)

            imap_conn = self.find_first(imap_conn_q)
            if imap_conn:
                imap_conn.update(v)
                return { 'imap_conn': imap_conn }
            return True


    def store(self, imap_conn):
        if 'disposition' not in imap_conn:
            if imap_conn.get('remote_auth_success') == 0 and \
               imap_conn.get('remote_auth_attempts') == 0:
                imap_conn.update({
                    'disposition': 'suspected_scanner',
                })
            
            elif imap_conn.get('remote_auth_success') == 0 and \
                 imap_conn.get('remote_auth_attempts', 0) > 0:
                imap_conn.update({
                    'disposition': 'failed_login_attempt',
                })

            elif imap_conn.get('connection_security') != 'TLS' and \
                 imap_conn.get('remote_ip') != '127.0.0.1':
                imap_conn.update({
                    'disposition': 'insecure'
                })
                
            else:
                imap_conn.update({
                    'disposition': 'ok',
                })                    

        drop = self.test_drop_disposition(imap_conn['disposition'])

        if not drop:
            log.debug('store: %s', imap_conn)
            try:
                self.record_store.store('imap_mail', imap_conn)
            except Exception as e:
                log.exception(e)
        
        self.remove_connection(imap_conn)


    def log_match(self, match_str, match_result, line):
        if match_result is True:
            log.info('%s [unmatched]: %s', match_str, line)
            
        elif match_result:
            if match_result.get('deferred', False):
                log.debug('%s [deferred]: %s', match_str, line)
                
            elif 'imap_conn' in match_result:
                log.debug('%s: %s: %s', match_str, line, match_result['imap_conn'])
            else:
                log.error('no imap_conn in match_result: ', match_result)
        else:
            log.debug('%s: %s', match_str, line)
                

    def test_end_of_rec(self, match_result):
        if not match_result or match_result is True or match_result.get('deferred', False):
            return False
        return self.end_of_rec(match_result['imap_conn'])
    
    def end_of_rec(self, imap_conn):
        '''a client must be disconnected for the record to be "complete"

        '''
        if 'disconnect_time' not in imap_conn:
            return False
        
        return True

    
    def handle(self, line):
        '''overrides ReadLineHandler method

        This function is called by the main log reading thread in
        TailFile. All additional log reading is blocked until this
        function completes.

        The storage engine (`record_store`, a SqliteEventStore
        instance) does not block, so this function will return before
        the record is saved to disk.

        IMPORTANT:

        The data structures and methods in this class are not thread
        safe. It is not okay to call any of them when the instance is
        registered with TailFile.

        '''
        if not self.capture_enabled:
            return

        self.update_inprogress_count()

        log.debug('imap recs in progress: %s', len(self.recs))
        
        match = self.match_connect_success(line)
        if match:
            self.log_match('connect', match, line)
            return

        match = self.match_connect_fail(line)
        if match:
            self.log_match('connect_fail', match, line)
            if self.test_end_of_rec(match):
                # we're done - not queued and disconnected ... save it
                self.store(match['imap_conn'])
            return

        match = self.match_disconnect(line)
        if match:
            self.log_match('disconnect', match, line)
            if self.test_end_of_rec(match):
                # we're done - not queued and disconnected ... save it
                self.store(match['imap_conn'])
            return

        if 'imap' in line:
            self.log_match('IGNORED', None, line)

