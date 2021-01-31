from .Timeseries import Timeseries
from .exceptions import InvalidArgsError
import logging

log = logging.getLogger(__name__)


def select_list_suggestions(conn, args):

    try:
        query_type = args['type']
        query = args['query'].strip()
        ts = None
        if 'start_date' in args:
            # use Timeseries to get a normalized start/end range
            ts = Timeseries(
                'select list suggestions',
                args['start_date'],
                args['end_date'],
                0
            )
    except KeyError:
        raise InvalidArgsError()

    # escape query with backslash for fuzzy match (LIKE)
    query_escaped = query.replace("\\", "\\\\").replace("%","\\%").replace("_","\\_")
    limit = 100

    queries = {
        'remote_host':  {
            'select': "DISTINCT CASE WHEN remote_host='unknown' THEN remote_ip ELSE remote_host END",
            'from': "mta_connection",
            'join': {},
            'order_by': "remote_host",
            'where_exact': [ "(remote_host = ? OR remote_ip = ?)" ],
            'args_exact': [ query, query ],
            'where_fuzzy': [ "(remote_host LIKE ? ESCAPE '\\' OR remote_ip LIKE ? ESCAPE '\\')" ],
            'args_fuzzy': [ '%'+query_escaped+'%', query_escaped+'%' ]
        },
        'rcpt_to': {
            'select': "DISTINCT rcpt_to",
            'from': 'mta_delivery',
            'join': {},
            'order_by': "rcpt_to",
            'where_exact': [ "rcpt_to = ?" ],
            'args_exact': [ query, ],
            'where_fuzzy': [ "rcpt_to LIKE ? ESCAPE '\\'" ],
            'args_fuzzy': [ '%'+query_escaped+'%' ]
        },
        'envelope_from': {
            'select': "DISTINCT envelope_from",
            'from': "mta_accept",
            'join': {},
            'order_by': 'envelope_from',
            'where_exact': [ "envelope_from = ?" ],
            'args_exact': [ query, ],
            'where_fuzzy': [ "envelope_from LIKE ? ESCAPE '\\'" ],
            'args_fuzzy': [ '%'+query_escaped+'%' ]
        },
    }

    q = queries.get(query_type)
    if not q:
        raise InvalidArgError()

    if ts:
        q['where_exact'] += [ 'connect_time>=?', 'connect_time<?' ]
        q['where_fuzzy'] += [ 'connect_time>=?', 'connect_time<?' ]
        q['args_exact'] += [ ts.start, ts.end ];
        q['args_fuzzy'] += [ ts.start, ts.end ];
        cur_join = q['from']
        if cur_join == 'mta_delivery':
            q['join']['mta_accept'] = "mta_accept.mta_accept_id = mta_delivery.mta_accept_id"
            cur_join = 'mta_accept'
            
        if cur_join == 'mta_accept':
            q['join']['mta_connection'] = "mta_connection.mta_conn_id = mta_accept.mta_conn_id"


    joins = []
    for table in q['join']:
        joins.append('JOIN ' + table + ' ON ' + q['join'][table])
    joins =" ".join(joins)

    c = conn.cursor()
    try:
        # 1. attempt to find an exact match first
        where = ' AND '.join(q['where_exact'])
        select = f"SELECT {q['select']} FROM {q['from']} {joins} WHERE {where} LIMIT {limit}"
        log.debug(select)
        c.execute(select, q['args_exact'])
        row = c.fetchone()
        if row:
            return {
                'exact': True,
                'suggestions': [ row[0] ],
                'limited': False
            }

        # 2. otherwise, do a fuzzy search and return all matches
        where = ' AND '.join(q['where_fuzzy'])
        select = f"SELECT {q['select']} FROM {q['from']} {joins} WHERE {where} ORDER BY {q['order_by']} LIMIT {limit}"
        log.debug(select)
        suggestions = []
        for row in c.execute(select, q['args_fuzzy']):
            suggestions.append(row[0])
        return {
            'exact': False,
            'suggestions': suggestions,
            'limited': len(suggestions)>=limit
        }
    
    finally:
        c.close()

