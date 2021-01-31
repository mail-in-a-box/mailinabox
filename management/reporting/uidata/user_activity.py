from .Timeseries import Timeseries
from .exceptions import InvalidArgsError

with open(__file__.replace('.py','.1.sql')) as fp:
    select_1 = fp.read()

with open(__file__.replace('.py','.2.sql')) as fp:
    select_2 = fp.read()


def user_activity(conn, args):
    '''
    details on user activity
    '''    
    try:
        user_id = args['user_id']

        # use Timeseries to get a normalized start/end range
        ts = Timeseries(
            'User activity',
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

    #
    # sent mail by user
    #
    c = conn.cursor()
    
    sent_mail = {
        'start': ts.start,
        'end': ts.end,
        'y': 'Sent mail',
        'fields': [
            # mta_connection
            'connect_time',
            'sasl_method',
            # mta_accept
            'envelope_from',
            # mta_delivery
            'rcpt_to',
            'service',
            'spam_score',
            'spam_result',
            'message_size',
            'status',
            'relay',
            'delivery_info',
            'delivery_connection',
            'delivery_connection_info',
            'sent_id',  # must be last
        ],
        'field_types': [
            { 'type':'datetime', 'format': '%Y-%m-%d %H:%M:%S' },# connect_time
            'text/plain',    # sasl_method
            'text/email',    # envelope_from
            { 'type':'text/email', 'label':'Recipient' },    # rcpt_to
            'text/plain',    # mta_delivery.service
            { 'type':'decimal', 'places':2 },     # spam_score
            'text/plain',    # spam_result
            'number/size',   # message_size
            'text/plain',    # status
            'text/hostname', # relay
            'text/plain',    # delivery_info
            'text/plain',    # delivery_connection
            'text/plain',    # delivery_connection_info
            'number/plain',  # sent_id - must be last
        ],
        'items': [],
        'unique_sends': 0
    }
    last_mta_accept_id = -1
    sent_id = 0
    for row in c.execute(select_1 + limit, {
            'user_id': user_id,
            'start_date': ts.start,
            'end_date': ts.end
    }):
        v = []
        for key in sent_mail['fields']:
            if key != 'sent_id':
                v.append(row[key])
        if last_mta_accept_id != row['mta_accept_id']:
            sent_mail['unique_sends'] += 1
            last_mta_accept_id = row['mta_accept_id']
            sent_id += 1
        v.append(sent_id)
        sent_mail['items'].append(v)


    #
    # received mail by user
    #

    received_mail = {
        'start': ts.start,
        'end': ts.end,
        'y': 'Sent mail',
        'fields': [
            # mta_connection
            'connect_time',
            'service',
            'sasl_username',
            
            # mta_accept
            'envelope_from',
            'disposition',
            'spf_result',
            'dkim_result',
            'dkim_reason',
            'dmarc_result',
            'dmarc_reason',
            
            # mta_delivery
            'orig_to',
            'postgrey_result',
            'postgrey_reason',
            'postgrey_delay',
            'spam_score',
            'spam_result',
            'message_size',
        ],
        'field_types': [
            { 'type':'datetime', 'format': '%Y-%m-%d %H:%M:%S' },# connect_time
            'text/plain',    # mta_connection.service
            'text/email',    # sasl_username
            'text/email',    # envelope_from
            'text/plain',    # disposition
            'text/plain',    # spf_result
            'text/plain',    # dkim_result
            'text/plain',    # dkim_result
            'text/plain',    # dmarc_result
            'text/plain',    # dmarc_result
            'text/email',    # orig_to
            'text/plain',    # postgrey_result
            'text/plain',    # postgrey_reason
            { 'type':'time/span', 'unit':'s' },   # postgrey_delay
            { 'type':'decimal', 'places':2 },     # spam_score
            'text/plain',    # spam_result
            'number/size',   # message_size
        ],
        'items': []
    }

    for row in c.execute(select_2 + limit, {
            'user_id': user_id,
            'start_date': ts.start,
            'end_date': ts.end
    }):
        v = []
        for key in received_mail['fields']:
            v.append(row[key])
        received_mail['items'].append(v)


        
    return {
        'sent_mail': sent_mail,
        'received_mail': received_mail
    }
