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


def remote_sender_activity(conn, args):
    '''
    details on remote senders (envelope from)
    '''    

    try:
        sender = args['sender']
        sender_type = args['sender_type']

        if sender_type not in ['email', 'server']:
            raise InvalidArgsError()

        # use Timeseries to get a normalized start/end range
        ts = Timeseries(
            'Remote sender activity',
            args['start_date'],
            args['end_date'],
            0
        )
    except KeyError:
        raise InvalidArgsError()

    # limit results
    try:
        limit = 'LIMIT ' + str(int(args.get('row_limit', 1000)));
    except ValueError:
        limit = 'LIMIT 1000'    

    c = conn.cursor()

    if sender_type == 'email':
        select = select_1
        fields = [
            # mta_connection
            'connect_time',
            'service',
            'sasl_username',
            # mta_delivery
            'rcpt_to',
            # mta_accept
            'disposition',
            'accept_status',
            'spf_result',
            'dkim_result',
            'dkim_reason',
            'dmarc_result',
            'dmarc_reason',
            'failure_info',
            'category',  # failure_category
            # mta_delivery
            'postgrey_result',
            'postgrey_reason',
            'postgrey_delay',
            'spam_score',
            'spam_result',
            'message_size',
            'sent_id',  # must be last
        ]
        field_types = [
            { 'type':'datetime', 'format': '%Y-%m-%d %H:%M:%S' },# connect_time
            'text/plain',    # service
            'text/plain',    # sasl_username
            { 'type':'text/email', 'label':'Recipient' },    # rcpt_to
            'text/plain',    # disposition
            'text/plain',    # accept_status
            'text/plain',    # spf_result
            'text/plain',    # dkim_result
            'text/plain',    # dkim_reason
            'text/plain',    # dmarc_result
            'text/plain',    # dmarc_reason
            'text/plain',    # failure_info
            'text/plain',    # category (mta_accept.failure_category)
            'text/plain',    # postgrey_result
            'text/plain',    # postgrey_reason
            { 'type':'time/span', 'unit':'s' }, # postgrey_delay
            { 'type':'decimal', 'places':2 },     # spam_score
            'text/plain',    # spam_result
            'number/size',   # message_size
            'number/plain',  # sent_id - must be last
        ]
        select_args = {
            'envelope_from': sender,
            'start_date': ts.start,
            'end_date': ts.end
        }

    elif sender_type == 'server':
        select = select_2
        fields = [
            # mta_connection
            'connect_time',
            # mta_accept
            'envelope_from',
            # mta_delivery
            'rcpt_to',
            'disposition',
            # mta_accept
            'accept_status',
            'spf_result',
            'dkim_result',
            'dkim_reason',
            'dmarc_result',
            'dmarc_reason',
            'failure_info',
            'category',  # failure_category
            # mta_delivery
            'postgrey_result',
            'postgrey_reason',
            'postgrey_delay',
            'spam_score',
            'spam_result',
            'message_size',
            'sent_id',  # must be last
        ]
        field_types = [
            { 'type':'datetime', 'format': '%Y-%m-%d %H:%M:%S' },# connect_time
            { 'type':'text/email', 'label':'From' },    # envelope_from
            { 'type':'text/email', 'label':'Recipient' },    # rcpt_to
            'text/plain',    # disposition
            'text/plain',    # accept_status
            'text/plain',    # spf_result
            'text/plain',    # dkim_result
            'text/plain',    # dkim_reason
            'text/plain',    # dmarc_result
            'text/plain',    # dmarc_reason
            'text/plain',    # failure_info
            'text/plain',    # category (mta_accept.failure_category)
            'text/plain',    # postgrey_result
            'text/plain',    # postgrey_reason
            { 'type':'time/span', 'unit':'s' }, # postgrey_delay
            { 'type':'decimal', 'places':2 },     # spam_score
            'text/plain',    # spam_result
            'number/size',   # message_size
            'number/plain',  # sent_id - must be last
        ]
        select_args = {
            'remote_host': sender,
            'start_date': ts.start,
            'end_date': ts.end
        }

        
    activity = {
        'start': ts.start,
        'end': ts.end,
        'y': 'Remote sender activity',
        'fields': fields,
        'field_types': field_types,
        'items': [],
        'unique_sends': 0
    }
    last_mta_accept_id = -1
    sent_id = 0
    for row in c.execute(select + limit, select_args):
        v = []
        for key in activity['fields']:
            if key != 'sent_id':
                v.append(row[key])
        if row['mta_accept_id'] is None or last_mta_accept_id != row['mta_accept_id']:
            activity['unique_sends'] += 1
            last_mta_accept_id = row['mta_accept_id']
            sent_id += 1
        v.append(sent_id)
        activity['items'].append(v)

        
    return {
        'activity': activity,
    }
