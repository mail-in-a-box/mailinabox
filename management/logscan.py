#!/usr/bin/python3

import argparse
import calendar
import gzip
import logging
import os
import pickle
import re
import shutil
import tempfile
import time
from collections import OrderedDict, defaultdict, Iterable
from datetime import datetime, timedelta
from functools import partial, lru_cache
from statistics import mean, stdev

from dateutil import parser
from dateutil.relativedelta import relativedelta

import utils

MONTHS = dict((v, k) for k, v in enumerate(calendar.month_abbr))

KNOWN_SERVICES = (
    "anvil",
    "auth",
    "auth-worker",
    "config",                   # Postfix config warning (anvil client limit warning encountered)
    "imap",
    "imap-login",
    "indexer",                  # Dovecot restart
    "indexer-worker",           # Dovecot indexer-worker process
    "lmtp",
    "log",                      # Dovecot restart
    "managesieve-login",
    "master",                   # Dovecot restart
    "opendkim",
    "opendmarc",
    "pop3",
    "pop3-login",
    "postfix/anvil",
    "postfix/bounce",
    "postfix/cleanup",
    "postfix/lmtp",
    "postfix/master",
    "postfix/pickup",
    "postfix/qmgr",
    "postfix/scache",
    "postfix/smtp",
    "postfix/smtpd",
    "postfix/submission/smtpd",
    "postfix/tlsmgr",
    "postgrey",
    "spampd",
    "ssl-params",               # Dovecot restart
)

LOG_DIR = '/var/log/'

LOG_FILES = [
    'mail.log',
    'mail.log.1',
    'mail.log.2.gz',
    'mail.log.3.gz',
    'mail.log.4.gz',
    'mail.log.5.gz',
    'mail.log.6.gz',
]

HISTORY_FILE = os.path.expanduser('~/.cache/logscan.cache')
HISTORY_SIZE = 30  # The number of days of history to remember

# Regular expressions used for log line parsing

MAIN_REGEX = re.compile(r"(\w+[\s]+\d+ \d+:\d+:\d+) ([\w]+ )?([\w\-/]+)[^:]*: (.*)")
SENT_REGEX = re.compile("([A-Z0-9]+): client=(\S+), sasl_method=(PLAIN|LOGIN), sasl_username=(\S+)")
RECV_REGEX = re.compile("([A-Z0-9]+): to=<(\S+)>, .* Saved")
CHCK_REGEX = re.compile("Info: Login: user=<(.*?)>, method=PLAIN, rip=(.*?),")
GREY_REGEX = re.compile("action=(greylist|pass), reason=(.*?), (?:delay=\d+, )?client_name=(.*), "
                        "client_address=(.*), sender=(.*), recipient=(.*)")
RJCT_REGEX = re.compile("NOQUEUE: reject: RCPT from .*?: (.*?); from=<(.*?)> to=<(.*?)>")


# Small helper functions, needed for pickling

def dd_list():
    return defaultdict(list)


def dd():
    return defaultdict(dd_list)


# Functions for extracting data from log lines produced by certain services

def scan_postfix_submission(collector, user_match, date, log):
    """ Parse a postfix submission log line

    Lines containing a sasl_method with the values 'PLAIN' or 'LOGIN' are assumed to indicate a sent email.

    """

    # Match both the 'plain' and 'login' sasl methods, since both authentication methods are allowed by Dovecot
    match = SENT_REGEX.match(log)

    if match:
        _, client, method, user = match.groups()
        user = user.lower()

        if user_match(user):
            # Get the user data, or create it if the user is new
            data = collector.setdefault(
                user,
                OrderedDict([
                    ('sent', 0),
                    ('hosts', 0),
                    ('first', None),
                    ('last', None),
                    ('by hour', defaultdict(int)),
                    ('host addresses', set()),
                ])
            )

            data['sent'] += 1
            data['host addresses'].add(client)
            data['hosts'] = len(data['host addresses'])
            data['by hour'][date.hour] += 1

            if data['last'] is None:
                data['last'] = date
            data['first'] = date


def scan_postfix_lmtp(collector, user_match, date, log):
    """ Parse a postfix lmtp log line

    It is assumed that every log of postfix/lmtp indicates an email that was successfully received by Postfix.

    """

    match = RECV_REGEX.match(log)

    if match:
        _, user = match.groups()
        user = user.lower()

        if user_match(user):
            # Get the user data, or create it if the user is new
            data = collector.setdefault(
                user,
                OrderedDict([
                    ('received', 0),
                    ('by hour', defaultdict(int)),
                    ('first', None),
                    ('last', None),
                ])
            )

            data['received'] += 1
            data['by hour'][date.hour] += 1

            if data['last'] is None:
                data['last'] = date
            data['first'] = date


def scan_login(collector, user_match, date, log):
    """ Scan a dovecot log line and extract interesting data """

    match = CHCK_REGEX.match(log)

    if match:
        user, rip = match.groups()
        user = user.lower()

        if user_match(user):
            # Get the user data, or create it if the user is new
            data = collector.setdefault(
                user,
                OrderedDict([
                    ('logins', 0),
                    ('by hour', defaultdict(int)),
                    ('first', None),
                    ('last', None),

                    ('by ip', defaultdict(int)),
                ])
            )

            data['logins'] += 1
            data['by hour'][date.hour] += 1

            if data['last'] is None:
                data['last'] = date
            data['first'] = date

            if rip not in ('127.0.0.1', '::1'):
                data['by ip'][rip] += 1
            else:
                data['by ip']['webmail'] += 1


def scan_greylist(collector, user_match, date, log):
    """ Scan a postgrey log line and extract interesting data """

    match = GREY_REGEX.match(log)

    if match:
        action, reason, sender_domain, sender_ip, sender_address, user = match.groups()
        user = user.lower()

        if user_match(user):
            # Get the user data, or create it if the user is new
            data = collector.setdefault(
                user,
                OrderedDict([
                    ('lost', 0),
                    ('pass', 0),
                    ('first', None),
                    ('last', None),
                    ('grey-list', {}),
                ])
            )

            # Might be useful to group services that use a lot of mail different servers on sub
            # domains like <sub>1.domein.com

            # if '.' in client_name:
            #     addr = client_name.split('.')
            #     if len(addr) > 2:
            #         client_name = '.'.join(addr[1:])

            if data['last'] is None:
                data['last'] = date
            data['first'] = date

            if len(sender_address) > 36:
                name, domain = sender_address.split('@')
                if len(name) > 12:
                    sender_address = name[:12] + '…@' + domain

            source = "✉ {} ← {}".format(sender_address, sender_ip if sender_domain == 'unknown' else sender_domain)

            if action == 'greylist' and reason == 'new':
                if source not in data['grey-list']:
                    data['lost'] += 1
                    data['grey-list'][source] = "✖ on {:%Y-%m-%d %H:%M:%S}".format(date)
            elif action == 'pass':
                data['pass'] += 1
                data['grey-list'][source] = "✔ on {:%Y-%m-%d %H:%M:%S}".format(date)


def scan_rejects(collector, known_addresses, user_match, date, log):
    """ Parse a postfix smtpd log line and extract interesting data

    Currently we search for received mails that were rejected.

    """

    # Check if the incoming mail was rejected

    match = RJCT_REGEX.match(log)

    if match:
        message, sender, user = match.groups()
        sender = sender or 'no address'
        user = user.lower()

        # skip this, if reported in the grey-listing report
        if 'Recipient address rejected: Greylisted' in message:
            return

        # only log mail to known recipients
        if user_match(user):
            if not known_addresses or user in known_addresses:
                data = collector.setdefault(
                    user,
                    OrderedDict([
                        ('blocked', 0),
                        ('from', OrderedDict()),
                        ('first', None),
                        ('last', None),
                    ])
                )
                # simplify this one
                match = re.search(r"Client host \[(.*?)\] blocked using zen.spamhaus.org; (.*)", message)
                if match:
                    message = "ip blocked: " + match.group(2)
                else:
                    # simplify this one too
                    match = re.search(r"Sender address \[.*@(.*)\] blocked using dbl.spamhaus.org; (.*)", message)
                    if match:
                        message = "domain blocked: " + match.group(2)

                if data['last'] is None:
                    data['last'] = date
                data['first'] = date
                data['blocked'] += 1
                data['from'][sender] = "✖ on {:%Y-%m-%d %H:%M:%S}: {}".format(date, message)


class Collector(dict):
    """ Custom dictionary class for collecting scan data """

    def __init__(self, start_date=None, end_date=None, filters=None, no_filter=False,
                 sent=True, received=True, imap=False, pop3=False, grey=False, rejected=False):

        super().__init__()

        # Try and get all the email addresses known to this box

        known_addresses = []

        if not no_filter:
            try:
                env_vars = utils.load_environment()
                import mailconfig
                known_addresses = sorted(
                    set(mailconfig.get_mail_users(env_vars)) |
                    set(alias[0] for alias in mailconfig.get_mail_aliases(env_vars)),
                    key=email_sort
                )
            except (FileNotFoundError, ImportError):
                pass

        start_date = start_date or datetime.now()
        end_date = end_date or start_date - timedelta(weeks=52)

        self.update({
            'end_of_file': False,                   # Indicates whether the end of the log files was reached
            'start_date': start_date,
            'end_date': end_date,
            'line_count': 0,                        # Number of lines scanned
            'parse_count': 0,                       # Number of lines parsed (i.e. that had their contents examined)
            'scan_time': time.time(),               # The time in seconds the scan took
            'unknown services': set(),              # Services encountered that were not recognized
            'known_addresses': known_addresses,     # Addresses handled by MiaB
            'services': {},                         # What services to scan for
            'data': OrderedDict(),                  # Scan data, per service
        })

        # Caching is only useful with longer filter lists, but doesn't seem to hurt performance in shorter ones
        user_match = lru_cache(maxsize=None)(partial(filter_match, [f.lower() for f in filters] if filters else None))

        if sent:
            data = {}
            self['data']['sent mail'] = {
                'scan': partial(scan_postfix_submission, data, user_match),
                'data': data,
            }
            self['services']['postfix/submission/smtpd'] = self['data']['sent mail']

        if received:
            data = {}
            self['data']['received mail'] = {
                'scan': partial(scan_postfix_lmtp, data, user_match),
                'data': data,
            }
            self['services']['postfix/lmtp'] = self['data']['received mail']

        if imap:
            data = {}
            self['data']['imap login'] = {
                'scan': partial(scan_login, data, user_match),
                'data': data,
            }
            self['services']['imap-login'] = self['data']['imap login']

        if pop3:
            data = {}
            self['data']['pop3 login'] = {
                'scan': partial(scan_login, data, user_match),
                'data': data,
            }
            self['services']['pop3-login'] = self['data']['pop3 login']

        if grey:
            data = {}
            self['data']['grey-listed mail'] = {
                'scan': partial(scan_greylist, data, user_match),
                'data': data,
            }
            self['services']['postgrey'] = self['data']['grey-listed mail']

        if rejected:
            data = {}
            self['data']['blocked mail'] = {
                'scan': partial(scan_rejects, data, self['known_addresses'], user_match),
                'data': data,
            }
            self['services']['postfix/smtpd'] = self['data']['blocked mail']

    def get_addresses(self, complete=False):
        addresses = set()
        for category in self['data']:
            try:
                for address in self['data'][category]['data']:
                    addresses.add(address)
            except KeyError:
                logging.debug("Category %s not found" % category)

        if complete:
            addresses.update(self['known_addresses'])
        return sorted(addresses, key=email_sort)

    def group_by_address(self, complete=False):

        addresses = self.get_addresses(complete)

        data = {}

        for address in addresses:
            data[address] = {}
            for category in self['data']:
                data[address][category] = self['data'][category]['data'].get(address, None)

        self['data'] = data


def scan_files(files, collector):
    """ Scan files until they run out or the earliest date is reached """

    logging.info("Scanning from {:%Y-%m-%d %H:%M:%S} back to {:%Y-%m-%d %H:%M:%S}".format(
        collector['start_date'], collector['end_date']
    ))

    for file_name in files:
        scan_file(file_name, collector)

    collector['scan_time'] = time.time() - collector["scan_time"]

    logging.info(
        "{line_count} Log lines scanned, {parse_count} lines parsed in {scan_time:.2f} seconds\n".format(**collector)
    )

    return collector


def scan_file(file_name, collector):

    if not os.path.exists(file_name):
        return

    logging.debug("Processing file %s...", file_name)

    collector['end_of_file'] = False

    with tempfile.NamedTemporaryFile() as tmp_file:

        # Copy the log file to a tmp file for scanning

        if file_name[-3:] == '.gz':
            shutil.copyfileobj(gzip.open(file_name), tmp_file)
        else:
            shutil.copyfileobj(open(file_name, 'rb'), tmp_file)

        file_name = tmp_file.name

        # A weird anomaly was encountered where a single log line with a much earlier date than the surrounding log
        # lines was found. To avoid this anomaly from halting the scan, the following variable was introduced.
        stop_scan = False

        for log_line in _reverse_readline(file_name):
            collector['line_count'] += 1

            # If the found date is earlier than the end date, return
            if _scan_mail_log_line(log_line.strip(), collector) is False:
                if stop_scan:
                    return
                stop_scan = True
            else:
                stop_scan = False

        # If we reached this part, the file was scanned completely
        collector['end_of_file'] = True


def parse_log_date(val, year):
    """ Custom log file date parsing, which is much faster than any generic function from the Python lib """

    try:
        return datetime(
            year,
            MONTHS[val[0:3]],
            int(val[4:6]),
            int(val[7:9]),
            int(val[10:12]),
            int(val[13:15])
        )
    except KeyError:
        logging.debug("Unknown month: %s", val)
        return None
    except ValueError:
        logging.debug("Irregular date found: %s", val)
        return None


def _scan_mail_log_line(line, collector):
    """ Scan a log line and extract interesting data

    Return False if the found date is earlier than the end date, True otherwise

    """

    m = MAIN_REGEX.match(line)

    if not m:
        return True

    date, hostname, service, log = m.groups()

    # logging.debug("date: %s, host: %s, service: %s, log: %s", date, hostname, service, log)

    date = parse_log_date(date, collector['start_date'].year)

    # Check if the found date is within the time span we are scanning
    if date is None or date > collector['start_date']:
        # Don't process, but continue
        return True
    elif date < collector['end_date']:
        # Don't process, and halt
        return False

    if service in collector['services']:
        collector['services'][service]['scan'](date, log)
        collector["parse_count"] += 1
    elif service not in KNOWN_SERVICES:
        if service not in collector["unknown services"]:
            collector["unknown services"].add(service)
            logging.debug("  Unknown service '%s':\n    %s", service, line)

    return True


def filter_match(filters, user):
    """ Check if the given user matches any of the filters """
    return filters is None or any(u in user for u in filters)


def email_sort(email):
    """ Split the given email address into a reverse order tuple, for sorting i.e (domain, name) """
    return tuple(reversed(email.split('@')))


def _reverse_readline(filename, buf_size=8192):
    """ A generator that returns the lines of a file in reverse order

    http://stackoverflow.com/a/23646049/801870

    """

    with open(filename) as fh:
        segment = None
        offset = 0
        fh.seek(0, os.SEEK_END)
        file_size = remaining_size = fh.tell()
        while remaining_size > 0:
            offset = min(file_size, offset + buf_size)
            fh.seek(file_size - offset)
            buff = fh.read(min(remaining_size, buf_size))
            remaining_size -= buf_size
            lines = buff.split('\n')
            # the first line of the buffer is probably not a complete line so
            # we'll save it and append it to the last line of the next buffer
            # we read
            if segment is not None:
                # if the previous chunk starts right from the beginning of line
                # do not concat the segment to the last line of new chunk
                # instead, yield the segment first
                if buff[-1] is not '\n':
                    lines[-1] += segment
                else:
                    yield segment
            segment = lines[0]
            for index in range(len(lines) - 1, 0, -1):
                if len(lines[index]):
                    yield lines[index]
        # Don't yield None if the file was empty
        if segment is not None:
            yield segment


def load_history(log_files, services, verbose=False):
    """ Load the pickled history dictionary from the cache file, or create it if it doesn't exist yet
    
    History dictionary structure:
    
    {
        last_date: date,
        last_mail: date,
        data:
            <address>: {
                <category>: {
                    <hour>: [count list],
                    <hour>: [count list],
                    <hour>: [count list],
                    .
                    .
                    .
                }
                <category>: {
                    <hour>: [count list],
                    <hour>: [count list],
                    <hour>: [count list],
                    .
                    .
                    .
                }
            }
    }
    
    """

    if os.path.exists(HISTORY_FILE):
        try:
            with open(HISTORY_FILE, 'rb') as f:
                history = pickle.load(f)
                last_date = history['last_date']
        except (TypeError, EOFError):
            os.remove(HISTORY_FILE)
            if verbose:
                mail_admin("History Error!", "History has been deleted")
            return None

        start_date = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0) - timedelta(days=1)
        end_date = start_date - timedelta(days=1)

        if last_date < start_date:

            history['last_date'] = start_date

            collectors = []

            while last_date < start_date:
                logging.info("Adding history for day %s", start_date)

                collector = scan_files(
                    log_files,
                    Collector(
                        start_date,
                        end_date,
                        **services
                    )
                )

                collectors.append(collector)

                if collector['end_of_file']:
                    break
                else:
                    start_date = end_date
                    end_date = start_date - timedelta(days=1)

            # Add them to the history, oldest first
            for collector in reversed(collectors):
                add_collector_to_history(collector, history)

            logging.debug('History updated')
            with open(HISTORY_FILE, 'wb') as f:
                pickle.dump(history, f)

            if verbose:
                mail_admin("History updated", history_to_str(history))
    else:
        history = {
            'last_date': None,
            'last_mail': None,
            'data': defaultdict(dd)
        }

        start_date = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0) - timedelta(days=1)
        end_date = start_date - timedelta(days=1)

        history['last_date'] = start_date

        collectors = []

        # Scan all log files
        while True:
            collector = scan_files(
                log_files,
                Collector(
                    start_date,
                    end_date,
                    **services
                )
            )

            collectors.append(collector)

            if collector['end_of_file']:
                break
            else:
                start_date = end_date
                end_date = start_date - timedelta(days=1)

        # Add them to the history, oldest first
        for collector in reversed(collectors):
            add_collector_to_history(collector, history)

        with open(HISTORY_FILE, 'wb') as f:
            pickle.dump(history, f)

        if verbose:
            mail_admin("History created", history_to_str(history))

    return history


def history_to_str(history):
    content = []
    for address, data in history['data'].items():
        content.append(address)
        for category, counts in data.items():
            content.append(' %s' % category)
            for hour, count in counts.items():
                content.append(' %s: %s' % (hour, count))
    return '\n'.join(content)


def add_collector_to_history(collector, history):

    collector.group_by_address(True)

    for collector_address, collector_data in collector['data'].items():
        # Get the dictionary of user data
        history_user_data = history['data'][collector_address]
        for collector_category in collector_data:
            history_user_category_data = history_user_data[collector_category]
            if collector_data[collector_category] and 'by hour' in collector_data[collector_category]:
                for hour in range(24):
                    history_user_category_data[hour].append(collector_data[collector_category]['by hour'][hour])
                    # Trim to last `HISTORY_SIZE` entries
                    history_user_category_data[hour] = history_user_category_data[hour][-HISTORY_SIZE:]
            else:
                for hour in range(24):
                    history_user_category_data[hour].append(0)
                    # Trim to last `HISTORY_SIZE` entries
                    history_user_category_data[hour] = history_user_category_data[hour][-HISTORY_SIZE:]


def count_is_suspect(count, history, threshold=0):
    """ Use three-sigma rule to detect anomalous count values 
    
    :param count: The number of emails counted in a certain hour    
    :type count: int
    :param history: List of counted emails in a certain hour over a number of days
    :type history: list
    :param threshold: The count value can only be suspect if it is higher than the threshold 
    :type threshold: int
    :return: True if suspect, False otherwise    
    :rtype: bool
    
    """

    if len(history) > 1 and count > threshold:
        mu = mean(history)
        std = stdev(history)
        # logging.debug("  mean: %s, std dev: %s", mu, std)
        return abs(count - mu) > 3 * std
    return False


def mail_admin(subject, content):
    import smtplib
    from email.message import Message
    from utils import load_environment

    env = load_environment()
    admin_addr = "administrator@" + env['PRIMARY_HOSTNAME']

    # create MIME message
    msg = Message()
    msg['From'] = "\"%s\" <%s>" % (env['PRIMARY_HOSTNAME'], admin_addr)
    msg['To'] = admin_addr
    msg['Subject'] = "[%s] %s" % (env['PRIMARY_HOSTNAME'], subject)
    msg.set_payload(content, "UTF-8")

    smtpclient = smtplib.SMTP('127.0.0.1', 25)
    smtpclient.ehlo()
    smtpclient.sendmail(
        admin_addr,  # MAIL FROM
        admin_addr,  # RCPT TO
        msg.as_string())
    smtpclient.quit()


def print_time_table(label, data):
    lbl_temp = "  │ {:<%d}" % max(len(label), 4)
    hour_line = [lbl_temp.format('hour')]
    data_line = [lbl_temp.format(label)]

    lines = ["  ┬"]

    for h in range(24):
        max_len = max(len(str(data[h])), 2)
        data_temp = "{:>%s}" % max_len

        hour_line.append(data_temp.format(h))
        data_line.append(data_temp.format(data[h] or '…'))

    lines.append(' '.join(hour_line))
    lines.append(' '.join(data_line))
    lines.append("  └" + (len(lines[-1]) - 3) * "─")

    return lines


def print_service_tables(collector, verbose=False):
    address_width = 24
    col_width = 8
    col_tmp = "{:>%d}" % col_width

    for service, service_data in collector['data'].items():

        # Gather data in a flat table and convert to strings

        if not service_data['data']:
            logging.info("\n✖ No %s data found", service)
            continue
        else:
            table = []

            data = service_data['data'].values()
            min_first = min([u["first"] for u in data])
            max_last = max([u["last"] for u in data])

            title = "{} ({:%Y-%m-%d %H:%M:%S} - {:%Y-%m-%d %H:%M:%S})".format(
                service.capitalize(),
                min_first,
                max_last
            )

            sorted_data = OrderedDict(sorted(service_data['data'].items(), key=lambda t: email_sort(t[0])))

            current_domain = ''

            accum = None

            for address, data in sorted_data.items():

                user, domain = address.split('@')

                if domain != current_domain:
                    header = '@%s %s' % (domain, '┄' * (64 - len(domain) - 3))
                    offset = 1 + address_width
                    num_atomic = len([v for v in data.values() if not isinstance(v, Iterable)])
                    offset += (num_atomic - 2) * col_width
                    if accum is None:
                        accum = [0] * (num_atomic - 1)
                    header = header[:offset] + '┼' + header[offset:]
                    table.append([header])
                    current_domain = domain

                tmp = "  {:<%d}" % (address_width - 2)
                row = [tmp.format(user[:address_width - 3] + "…" if len(user) > address_width else user)]

                # Condense first and last date points into a time span
                first = data.pop("first")
                last = data.pop("last")

                timespan = relativedelta(last, first)

                if timespan.months:
                    timespan_str = " │ {:0.1f} months".format(timespan.months + timespan.days / 30.0)
                elif timespan.days:
                    timespan_str = " │ {:0.1f} days".format(timespan.days + timespan.hours / 24.0)
                elif (first.hour, first.minute) == (last.hour, last.minute):
                    timespan_str = " │ {:%H:%M}".format(first)
                else:
                    timespan_str = " │ {:%H:%M} - {:%H:%M}".format(first, last)

                accum[0] += 1

                # Only consider flat data in a flat table
                for name, value in data.items():
                    if isinstance(value, (int, float)):
                        accum[len(row)] += value
                        row.append(col_tmp.format(value))

                row.append(timespan_str)
                data[' │ timespan'] = timespan
                table.append(row)

                if verbose:
                    for name, value in data.items():
                        if isinstance(value, Iterable):
                            if name == 'by hour':
                                table.extend(print_time_table(service, data['by hour']))
                            else:
                                if name == 'by ip':
                                    value = ["{:<16}{:>4}".format(*v) for v in value.items()]

                                table.append("  ┬")
                                table.append("  │ %s" % name)
                                table.append("  ├─%s" % (len(name) * "─"))
                                max_len = 0

                                if isinstance(value, dict):
                                    for key, val in value.items():
                                        key_output = str(key)
                                        val_output = str(val)
                                        table.append("  │ %s" % key_output)
                                        table.append("  │   %s" % val_output)
                                        max_len = max(max_len, len(key_output), len(val_output))
                                else:
                                    for item in value:
                                        table.append("  │ %s" % str(item))
                                        max_len = max(max_len, len(str(item)))
                                table.append("  └" + (max_len + 1) * "─")

            header = [" " * address_width]
            header.extend([col_tmp.format(k) for k, v in data.items() if not isinstance(v, Iterable)])

            table.insert(0, header)

        # Print table

        print_table = [
            '',
            title,
            "═" * offset + '╤' + "═" * (64 - offset - 1),
        ]

        for row in table:
            print_table.append(''.join(row))

        print_table.append("─" * offset + '┴' + "─" * (64 - offset - 1),)

        accum[0] = tmp.format("Totals: {}".format(accum[0]))
        accum = [col_tmp.format(v) for v in accum]
        print_table.append(''.join(accum))

        logging.info('\n'.join(print_table))
    return


def command_run():

    logger = logging.getLogger()
    ch = logging.StreamHandler()
    formatter = logging.Formatter('%(message)s')
    ch.setFormatter(formatter)
    logger.addHandler(ch)

    def valid_date(string):
        """ Validate the given date string fetched from the --startdate argument """
        try:
            date = parser.parse(string)
        except ValueError:
            raise argparse.ArgumentTypeError("Unrecognized date and/or time '%s'" % string)
        return date

    start_date = datetime.now()

    time_deltas = OrderedDict([
        ('all', timedelta(weeks=52)),
        ('month', timedelta(weeks=4)),
        ('2weeks', timedelta(days=14)),
        ('week', timedelta(days=7)),
        ('2days', timedelta(days=2)),
        ('day', timedelta(days=1)),
        ('12hours', timedelta(hours=12)),
        ('6hours', timedelta(hours=6)),
        ('hour', timedelta(hours=1)),
        ('30min', timedelta(minutes=30)),
        ('10min', timedelta(minutes=10)),
        ('5min', timedelta(minutes=5)),
        ('min', timedelta(minutes=1)),
        ('today', start_date - start_date.replace(hour=0, minute=0, second=0))
    ])

    ap = argparse.ArgumentParser(
        description="Scan the mail log files for interesting data. By default, this script "
                    "shows today's incoming and outgoing mail statistics. This script was ("
                    "re)written for the Mail-in-a-box email server."
                    "https://github.com/mail-in-a-box/mailinabox",
        add_help=False
    )

    # Switches to determine what to parse and what to ignore

    ap.add_argument("-a", "--all", help="Scan for all services.", action="store_true")
    ap.add_argument("-r", "--received", help="Scan for received emails.", action="store_true")
    ap.add_argument("-s", "--sent", help="Scan for sent emails.", action="store_true")
    ap.add_argument("-l", "--logins", help="Scan for IMAP and POP3 logins.", action="store_true")
    ap.add_argument("-i", "--imap", help="Scan for IMAP logins.", action="store_true")
    ap.add_argument("-p", "--pop3", help="Scan for POP3 logins.", action="store_true")
    ap.add_argument("-g", "--grey", help="Scan for greylisted emails.", action="store_true")
    ap.add_argument("-b", "--blocked", help="Scan for blocked emails.", action="store_true")

    ap.add_argument("-f", "--file", help="Path to a log file.", dest="log_files", metavar='<path>', action="append")

    ap.add_argument("-m", "--monitor", nargs='?', const=50, type=int, metavar='<threshold>',
                    help="Mail an alert to the administrator when unusual behaviour is suspected. The optional "
                         "threshold value sets a limit above which the number of emails sent or received per hour by a "
                         "user will be evaluated. The default threshold is 50. It's recommended to use this option in "
                         "a cron job, e.g. '*/5 * * * * <path to>/logscan.py -m', which will run every 5 minutes.")
    ap.add_argument("-t", "--timespan", choices=time_deltas.keys(), default='today', metavar='<time span>',
                    help="Time span to scan, going back from the start date. Possible values: "
                         "{}. Defaults to 'today'.".format(", ".join(list(time_deltas.keys()))))
    ap.add_argument("-d", "--startdate",  action="store", dest="startdate", type=valid_date, metavar='<start date>',
                    help="Date and time to start scanning the log file from. If no date is "
                          "provided, scanning will start from the current date and time.")
    ap.add_argument("-u", "--users", action="store", dest="users", metavar='<email1,email2,email...>',
                    help="Comma separated list of (partial) email addresses to filter the output by.")

    ap.add_argument('-n', "--nofilter", help="Don't filter by known email addresses.", action="store_true")
    ap.add_argument('-h', '--help', action='help', help="Print this message and exit.")
    ap.add_argument("-v", "--verbose", help="Output extra data where available.", action="store_true")

    args = ap.parse_args()

    logger.setLevel(logging.DEBUG if args.verbose else logging.INFO)

    # Set a custom start date, but ignore it in monitor mode
    if args.startdate is not None and args.monitor is None:
        start_date = args.startdate
        # Change the 'today' time span to 'day' when a custom start date is set
        if args.timespan == 'today':
            args.timespan = 'day'
        logging.info("Setting start date to {}".format(start_date))

    end_date = start_date - time_deltas[args.timespan]

    filters = None

    if args.users is not None:
        filters = args.users.strip().split(',')
        logging.info("Filtering with '%s'", ", ".join(filters))

    services = {}

    if args.monitor is not None:
        # Set the services that will be checked in monitor mode
        services = {
            'sent': True,
            'received': True,
            'grey': False,
            'rejected': False,
            'imap': False,
            'pop3': False
        }
    elif True in (args.all, args.received, args.sent, args.logins, args.pop3, args.imap, args.grey, args.blocked):

        services = {
            'sent': args.sent or args.all,
            'received': args.received or args.all,
            'grey': args.grey or args.all,
            'rejected': args.blocked or args.all,
            'imap': args.imap or args.logins or args.all,
            'pop3': args.pop3 or args.logins or args.all
        }

        # Print what data is going to be processed

        service_names = []
        logins = []

        if services['sent']:
            service_names.append("sent")

        if services['received']:
            service_names.append("received")

        if services['grey']:
            service_names.append("grey-listed")

        if services['rejected']:
            service_names.append("rejected")

        if services['imap']:
            logins.append("IMAP")

        if services['pop3']:
            logins.append("POP3")

        message = "Scanning for"

        if service_names:
            message = "{} {} emails".format(message, ', '.join(service_names))
            if logins:
                message = "{} and {} logins".format(message, ', '.join(logins))
        elif logins:
            message = "{} {} logins".format(message, ', '.join(logins))

        logging.info(message)

    if args.monitor is not None:
        # Load activity history

        history = load_history(
            args.log_files or [os.path.join(LOG_DIR, f) for f in LOG_FILES],
            services,
            args.verbose
        )

        # for a, d in history['data'].items():
        #     print(a)
        #     print([len(v) for k, v in d['sent mail'].items()])

        # Fetch today's activity

        col = scan_files(
            args.log_files or [os.path.join(LOG_DIR, f) for f in LOG_FILES],
            Collector(
                start_date,
                end_date,
                filters,
                args.nofilter,
                **services
            )
        )
        col.group_by_address(True)

        # Compare today with history

        report = []

        now = datetime.now()
        if history['last_mail'] is None or now - history['last_mail'] > timedelta(hours=0.5):
            for address, data in col['data'].items():
                sub_report = [address]
                for category, cat_data in data.items():
                    # If we have 'by hour' data for the current category *and* the current address has a history
                    if cat_data and 'by hour' in cat_data:
                        # Fetch the count of the latest hour
                        hour, count = max(cat_data['by hour'].items())
                        if count_is_suspect(count, history['data'][address][category][hour], args.monitor):
                            msg = "  Found %d %ss at %d:00 where %0.2f is the average"
                            msg %= count, category, hour, mean(history['data'][address][category][hour])
                            sub_report.append(msg)
                if len(sub_report) > 1:
                    report.extend(sub_report)

            if report:
                report.extend([
                    "\nReset the history by deleting the '%s' file" % HISTORY_FILE,
                    "The current limit for warnings is %d emails per hour." % args.monitor,
                ])
                content = '\n'.join(report)
                logging.info("Suspicious activity activity!")
                logging.debug(content)
                mail_admin("Suspicious email activity!", content)

                history['last_mail'] = now
                with open(HISTORY_FILE, 'wb') as f:
                    pickle.dump(history, f)
    else:
        col = scan_files(
            args.log_files or [os.path.join(LOG_DIR, f) for f in LOG_FILES],
            Collector(
                start_date,
                end_date,
                filters,
                args.nofilter,
                **services
            )
        )

        print_service_tables(col, args.verbose)


if __name__ == "__main__":
    command_run()
