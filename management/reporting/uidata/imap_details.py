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


def imap_details(conn, args):
    '''
    details on imap connections
    '''    
    try:
        user_id = args['user_id']

        # use Timeseries to get a normalized start/end range
        ts = Timeseries(
            'IMAP details',
            args['start_date'],
            args['end_date'],
            0
        )

        # optional
        remote_host = args.get('remote_host')
        disposition = args.get('disposition')
        
    except KeyError:
        raise InvalidArgsError()

    # limit results
    try:
        limit = 'LIMIT ' + str(int(args.get('row_limit', 1000)));
    except ValueError:
        limit = 'LIMIT 1000'


    c = conn.cursor()

    imap_details = {
        'start': ts.start,
        'end': ts.end,
        'y': 'IMAP Details',
        'fields': [
            'connect_time',
            'disconnect_time',
            'remote_host',
            'sasl_method',
            'disconnect_reason',
            'connection_security',
            'disposition',
            'in_bytes',
            'out_bytes'
        ],
        'field_types': [
            { 'type':'datetime', 'format': ts.parsefmt }, # connect_time
            { 'type':'datetime', 'format': ts.parsefmt }, # disconnect_time
            'text/plain',    # remote_host
            'text/plain',    # sasl_method
            'text/plain',    # disconnect_reason
            'text/plain',    # connection_security
            'text/plain',    # disposition
            'number/size',   # in_bytes,
            'number/size',   # out_bytes,
        ],
        'items': []
    }

    for row in c.execute(select_1 + limit, {
            'user_id': user_id,
            'start_date': ts.start,
            'end_date': ts.end,
            'remote_host': remote_host,
            'disposition': disposition
    }):
        v = []
        for key in imap_details['fields']:
            v.append(row[key])
        imap_details['items'].append(v)

    
    return {
        'imap_details': imap_details
    }
