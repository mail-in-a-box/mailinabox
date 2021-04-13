from .Timeseries import Timeseries
from .exceptions import InvalidArgsError
from .top import select_top

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


    
def messages_received(conn, args):
    '''
    messages recived from the internet

    '''
    try:
        ts = Timeseries(
            "Messages received from the internet",
            args['start'],
            args['end'],
            args['binsize']
        )
    except KeyError:
        raise InvalidArgsError()

    s_received = ts.add_series('received', 'messages received')
    
    c = conn.cursor()
    try:
        for row in c.execute(select_1.format(timefmt=ts.timefmt), {
                'start_date':ts.start,
                'end_date':ts.end,
                'start_unixepoch':ts.start_unixepoch,
                'binsize':ts.binsize
        }):
            idx = ts.insert_date(row['bin'])
            s_received['values'][idx] = row['count']


        # top 10 senders (envelope_from) by message count
        top_senders_by_count = select_top(
            c,
            select_2,
            ts.start,
            ts.end,
            "Top 10 senders by count",
            [ 'email', 'count' ],
            [ 'text/email', 'number/plain' ]
        )
        
        # top 10 senders (envelope_from) by message size
        top_senders_by_size = select_top(
            c,
            select_3,
            ts.start,
            ts.end,
            "Top 10 senders by size",
            [ 'email', 'size' ],
            [ 'text/email', 'number/size' ]
        )

        # top 10 remote servers/domains (remote hosts) by average spam score
        top_hosts_by_spam_score = select_top(
            c,
            select_4,
            ts.start,
            ts.end,
            "Top servers by average spam score",
            [ 'remote_host', 'avg_spam_score' ],
            [ 'text/hostname', { 'type':'decimal', 'places':2} ]
        )
        
        # top 10 users receiving the most spam
        top_user_receiving_spam = select_top(
            c,
            select_5,
            ts.start,
            ts.end,
            "Top 10 users receiving spam",
            [
                'rcpt_to',
                'count'
            ],
            [
                { 'type': 'text', 'subtype':'email', 'label':'User' },
                'number/plain'
            ]
        )

    finally:
        c.close()

    return {
        'top_senders_by_count': top_senders_by_count,
        'top_senders_by_size': top_senders_by_size,
        'top_hosts_by_spam_score': top_hosts_by_spam_score,
        'top_user_receiving_spam': top_user_receiving_spam,
        'ts_received': ts.asDict(),
    }
