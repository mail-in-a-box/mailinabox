#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####

from .Timeseries import Timeseries
from .exceptions import InvalidArgsError

with open(__file__.replace('.py','.1.sql')) as fp:
    select_1 = fp.read()
    
with open(__file__.replace('.py','.2.sql')) as fp:
    select_2 = fp.read()

with open(__file__.replace('.py','.3.sql')) as fp:
    select_3 = fp.read()
    
with open(__file__.replace('.py','.4.sql')) as fp:
    select_4 = fp.read()
    

def messages_sent(conn, args):
    '''
    messages sent by local users
      - delivered locally & remotely

    '''
    try:
        ts = Timeseries(
            "Messages sent by users",
            args['start'],
            args['end'],
            args['binsize']
        )
    except KeyError:
        raise InvalidArgsError()

    s_sent = ts.add_series('sent', 'messages sent')
    s_local = ts.add_series('local', 'local recipients')
    s_remote = ts.add_series('remote', 'remote recipients')
    
    c = conn.cursor()
    try:
        for row in c.execute(select_1.format(timefmt=ts.timefmt), {
                'start_date':ts.start,
                'end_date':ts.end,
                'start_unixepoch':ts.start_unixepoch,
                'binsize':ts.binsize
        }):
            idx = ts.insert_date(row['bin'])
            s_sent['values'][idx] = row['sent_count']

        date_idx = -1

        # the returned bins are the same as select_1 because the
        # querie's WHERE and JOINs are the same
        for row in c.execute(select_2.format(timefmt=ts.timefmt), {
                'start_date':ts.start,
                'end_date':ts.end,
                'start_unixepoch':ts.start_unixepoch,
                'binsize':ts.binsize
        }):
            date_idx = ts.insert_date(row['bin'])
            if row['delivery_service']=='smtp':
                s_remote['values'][date_idx] = row['delivery_count']
            elif row['delivery_service']=='lmtp':
                s_local['values'][date_idx] = row['delivery_count']
                

        top_senders1 = {
            'start': ts.start,
            'end': ts.end,
            'y': 'Top 10 users by count',
            'fields': ['user','count'],
            'field_types': ['text/email','number/plain'],
            'items': []
        }
        for row in c.execute(select_3, {
                'start_date':ts.start,
                'end_date':ts.end
        }):
            top_senders1['items'].append({
                'user': row['username'],
                'count': row['count']
            })
            
        top_senders2 = {
            'start': ts.start,
            'end': ts.end,
            'y': 'Top 10 users by size',
            'fields': ['user','size'],
            'field_types': ['text/email','number/size'],
            'items': []
        }
        for row in c.execute(select_4, {
                'start_date':ts.start,
                'end_date':ts.end
        }):
            top_senders2['items'].append({
                'user': row['username'],
                'size': row['message_size_total']
            })

    finally:
        c.close()

    return {
        'top_senders_by_count': top_senders1,
        'top_senders_by_size': top_senders2,
        'ts_sent': ts.asDict(),
    }
