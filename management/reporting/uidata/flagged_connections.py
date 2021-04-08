import logging
from .Timeseries import Timeseries
from .exceptions import InvalidArgsError
from .top import select_top

log = logging.getLogger(__name__)

with open(__file__.replace('.py','.1.sql')) as fp:
    select_1 = fp.read()

with open(__file__.replace('.py','.2.sql')) as fp:
    select_2 = fp.read()

with open(__file__.replace('.py','.3.sql')) as fp:
    select_3 = fp.read()

with open(__file__.replace('.py','.4.sql')) as fp:
    select_4 = fp.read()

with open(__file__.replace('.py','.5.sql')) as fp:
    select_5 = fp.read()

with open(__file__.replace('.py','.6.sql')) as fp:
    select_6 = fp.read()

with open(__file__.replace('.py','.7.sql')) as fp:
    select_7 = fp.read()


def flagged_connections(conn, args):
    try:
        ts = Timeseries(
            "Failed login attempts and suspected scanners over time",
            args['start'],
            args['end'],
            args['binsize']
        )
    except KeyError:
        raise InvalidArgsError()

    c = conn.cursor()
    
    # pie chart for "connections by disposition"
    connections_by_disposition = []
    for row in c.execute(select_7, {'start_date':ts.start, 'end_date':ts.end}):
        connections_by_disposition.append({
            'name': row[0],
            'value': row[1]
        })

    # timeseries = failed logins count
    s_failed_login = ts.add_series('failed_login_attempt', 'failed login attempts')
    sql = select_1.format(timefmt=ts.timefmt)
    for row in c.execute(sql, {
            'start_date': ts.start,
            'end_date': ts.end,
            'start_unixepoch': ts.start_unixepoch,
            'binsize': ts.binsize
    }):
        idx = ts.insert_date(row['bin'])
        s_failed_login['values'][idx] = row['count']

    # timeseries = suspected scanners count
    s_scanner = ts.add_series('suspected_scanner', 'connections by suspected scanners')
    sql = select_2.format(timefmt=ts.timefmt)
    for row in c.execute(sql, {
            'start_date': ts.start,
            'end_date': ts.end,
            'start_unixepoch': ts.start_unixepoch,
            'binsize': ts.binsize
    }):
        idx = ts.insert_date(row['bin'])
        s_scanner['values'][idx] = row['count']


    # pie chart for "disposition=='reject' grouped by failure_category"
    reject_by_failure_category = []
    for row in c.execute(select_3, {
            'start_date': ts.start,
            'end_date': ts.end
    }):
        reject_by_failure_category.append({
            'name': row[0],
            'value': row[1]
        })
        
    # top 10 servers rejected by category
    top_hosts_rejected = select_top(
        c,
        select_4,
        ts.start,
        ts.end,
        "Top servers rejected by category",
        [ 'remote_host', 'category', 'count' ],
        [ 'text/hostname', 'text/plain', 'number/plain' ]
    )

    # insecure inbound connections - no limit
    insecure_inbound = select_top(
        c,
        select_5,
        ts.start,
        ts.end,
        "Insecure inbound connections (no use of STARTTLS)",
        [
            'service',
            'sasl_username',
            'envelope_from',
            'rcpt_to',
            'count'
        ],
        [
            'text/plain', # service
            'text/plain', # sasl_username
            'text/email', # envelope_from
            { 'type':'text/email', 'label':'Recipient' }, # rcpt_to
            'number/plain', # count
        ]
    )

    # insecure outbound connections - no limit
    insecure_outbound = select_top(
        c,
        select_6,
        ts.start,
        ts.end,
        "Insecure outbound connections (low grade encryption)",
        [
            'service',
            'sasl_username',
            'envelope_from',
            'rcpt_to',
            'count'
        ],
        [
            'text/plain', # service
            'text/plain', # sasl_username
            'text/email', # envelope_from
            { 'type':'text/email', 'label':'Recipient' }, # rcpt_to
            'number/plain', # count
        ]
    )


    
    return {
        'connections_by_disposition': connections_by_disposition,
        'flagged': ts.asDict(),
        'reject_by_failure_category': reject_by_failure_category,
        'top_hosts_rejected': top_hosts_rejected,
        'insecure_inbound': insecure_inbound,
        'insecure_outbound': insecure_outbound,
    }
