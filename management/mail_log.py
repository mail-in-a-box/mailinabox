#!/usr/bin/python3

import os.path
import re
from collections import defaultdict

import dateutil.parser

import mailconfig
import utils


def scan_mail_log(logger, env):
    """ Scan the system's mail log files and collect interesting data

    This function scans the 2 most recent mail log files in /var/log/.

    Args:
        logger (ConsoleOutput): Object used for writing messages to the console
        env (dict): Dictionary containing MiaB settings
    """

    collector = {
        "other-services": set(),
        "imap-logins": {},
        "pop3-logins": {},
        "postgrey": {},
        "rejected-mail": {},
        "activity-by-hour": {
            "imap-logins": defaultdict(int),
            "pop3-logins": defaultdict(int),
            "smtp-sends": defaultdict(int),
            "smtp-receives": defaultdict(int),
        },
        "real_mail_addresses": (
            set(mailconfig.get_mail_users(env)) | set(alias[0] for alias in mailconfig.get_mail_aliases(env))
        )
    }

    for fn in ('/var/log/mail.log.1', '/var/log/mail.log'):
        if not os.path.exists(fn):
            continue
        with open(fn, 'rb') as log:
            for line in log:
                line = line.decode("utf8", errors='replace')
                scan_mail_log_line(line.strip(), collector)

    if collector["imap-logins"]:
        logger.add_heading("Recent IMAP Logins")
        logger.print_block("The most recent login from each remote IP adddress is shown.")
        for k in utils.sort_email_addresses(collector["imap-logins"], env):
            for ip, date in sorted(collector["imap-logins"][k].items(), key=lambda kv: kv[1]):
                logger.print_line(k + "\t" + str(date) + "\t" + ip)

    if collector["pop3-logins"]:
        logger.add_heading("Recent POP3 Logins")
        logger.print_block("The most recent login from each remote IP adddress is shown.")
        for k in utils.sort_email_addresses(collector["pop3-logins"], env):
            for ip, date in sorted(collector["pop3-logins"][k].items(), key=lambda kv: kv[1]):
                logger.print_line(k + "\t" + str(date) + "\t" + ip)

    if collector["postgrey"]:
        logger.add_heading("Greylisted Mail")
        logger.print_block("The following mail was greylisted, meaning the emails were temporarily rejected. "
                           "Legitimate senders will try again within ten minutes.")
        logger.print_line("recipient" + "\t" + "received" + 3 * "\t" + "sender" + 6 * "\t" + "delivered")
        for recipient in utils.sort_email_addresses(collector["postgrey"], env):
            sorted_recipients = sorted(collector["postgrey"][recipient].items(), key=lambda kv: kv[1][0])
            for (client_address, sender), (first_date, delivered_date) in sorted_recipients:
                logger.print_line(
                    recipient + "\t" + str(first_date) + "\t" + sender + "\t" +
                    (("delivered " + str(delivered_date)) if delivered_date else "no retry yet")
                )

    if collector["rejected-mail"]:
        logger.add_heading("Rejected Mail")
        logger.print_block("The following incoming mail was rejected.")
        for k in utils.sort_email_addresses(collector["rejected-mail"], env):
            for date, sender, message in collector["rejected-mail"][k]:
                logger.print_line(k + "\t" + str(date) + "\t" + sender + "\t" + message)

    logger.add_heading("Activity by Hour")
    logger.print_block("Dovecot logins and Postfix mail traffic per hour.")
    logger.print_block("Hour\tIMAP\tPOP3\tSent\tReceived")
    for h in range(24):
        logger.print_line(
            "%d\t%d\t\t%d\t\t%d\t\t%d" % (
                h,
                collector["activity-by-hour"]["imap-logins"][h],
                collector["activity-by-hour"]["pop3-logins"][h],
                collector["activity-by-hour"]["smtp-sends"][h],
                collector["activity-by-hour"]["smtp-receives"][h],
            )
        )

    if len(collector["other-services"]) > 0:
        logger.add_heading("Other")
        logger.print_block("Unrecognized services in the log: " + ", ".join(collector["other-services"]))


def scan_mail_log_line(line, collector):
    """ Scan a log line and extract interesting data """

    m = re.match(r"(\S+ \d+ \d+:\d+:\d+) (\S+) (\S+?)(\[\d+\])?: (.*)", line)

    if not m:
        return

    date, system, service, pid, log = m.groups()
    date = dateutil.parser.parse(date)

    if service == "dovecot":
        scan_dovecot_line(date, log, collector)
    elif service == "postgrey":
        scan_postgrey_line(date, log, collector)
    elif service == "postfix/smtpd":
        scan_postfix_smtpd_line(date, log, collector)
    elif service == "postfix/cleanup":
        scan_postfix_cleanup_line(date, log, collector)
    elif service == "postfix/submission/smtpd":
        scan_postfix_submission_line(date, log, collector)
    elif service in ("postfix/qmgr", "postfix/pickup", "postfix/cleanup", "postfix/scache", "spampd", "postfix/anvil",
                     "postfix/master", "opendkim", "postfix/lmtp", "postfix/tlsmgr"):
        # nothing to look at
        pass
    else:
        collector["other-services"].add(service)


def scan_dovecot_line(date, line, collector):
    """ Scan a dovecot log line and extract interesting data """

    m = re.match("(imap|pop3)-login: Login: user=<(.*?)>, method=PLAIN, rip=(.*?),", line)

    if m:
        prot, login, ip = m.group(1), m.group(2), m.group(3)
        logins_key = "%s-logins" % prot
        if ip != "127.0.0.1":  # local login from webmail/zpush
            collector[logins_key].setdefault(login, {})[ip] = date
        collector["activity-by-hour"][logins_key][date.hour] += 1


def scan_postgrey_line(date, log, collector):
    """ Scan a postgrey log line and extract interesting data """

    m = re.match("action=(greylist|pass), reason=(.*?), (?:delay=\d+, )?client_name=(.*), client_address=(.*), "
                 "sender=(.*), recipient=(.*)",
                 log)

    if m:
        action, reason, client_name, client_address, sender, recipient = m.groups()
        key = (client_address, sender)
        if action == "greylist" and reason == "new":
            collector["postgrey"].setdefault(recipient, {})[key] = (date, None)
        elif action == "pass" and reason == "triplet found" and key in collector["postgrey"].get(recipient, {}):
            collector["postgrey"][recipient][key] = (collector["postgrey"][recipient][key][0], date)


def scan_postfix_smtpd_line(date, log, collector):
    """ Scan a postfix smtpd log line and extract interesting data """

    # Check if the incomming mail was rejected

    m = re.match("NOQUEUE: reject: RCPT from .*?: (.*?); from=<(.*?)> to=<(.*?)>", log)

    if m:
        message, sender, recipient = m.groups()
        if recipient in collector["real_mail_addresses"]:
            # only log mail to real recipients

            # skip this, if reported in the greylisting report
            if "Recipient address rejected: Greylisted" in message:
                return

            # simplify this one
            m = re.search(r"Client host \[(.*?)\] blocked using zen.spamhaus.org; (.*)", message)
            if m:
                message = "ip blocked: " + m.group(2)

            # simplify this one too
            m = re.search(r"Sender address \[.*@(.*)\] blocked using dbl.spamhaus.org; (.*)", message)
            if m:
                message = "domain blocked: " + m.group(2)

            collector["rejected-mail"].setdefault(recipient, []).append((date, sender, message))


def scan_postfix_cleanup_line(date, _, collector):
    """ Scan a postfix cleanup log line and extract interesting data

    It is assumed that every log of postfix/cleanup indicates an email that was successfulfy received by Postfix.

    """

    collector["activity-by-hour"]["smtp-receives"][date.hour] += 1

def scan_postfix_submission_line(date, log, collector):
    """ Scan a postfix submission log line and extract interesting data """

    m = re.match("([A-Z0-9]+): client=(\S+), sasl_method=PLAIN, sasl_username=(\S+)", log)

    if m:
        # procid, client, user = m.groups()
        collector["activity-by-hour"]["smtp-sends"][date.hour] += 1


if __name__ == "__main__":
    from status_checks import ConsoleOutput

    env_vars = utils.load_environment()
    scan_mail_log(ConsoleOutput(), env_vars)
