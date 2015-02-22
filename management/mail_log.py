#!/usr/bin/python3

import re
import os.path
import dateutil.parser

import mailconfig
import utils


def scan_mail_log(logger, env):
    collector = {
        "other-services": set(),
        "imap-logins": {},
        "postgrey": {},
        "rejected-mail": {},
    }

    collector["real_mail_addresses"] = set(mailconfig.get_mail_users(env)) | set(alias[0] for alias in mailconfig.get_mail_aliases(env))

    for fn in ('/var/log/mail.log.1', '/var/log/mail.log'):
        if not os.path.exists(fn):
            continue
        with open(fn, 'rb') as log:
            for line in log:
                line = line.decode("utf8", errors='replace')
                scan_mail_log_line(line.strip(), collector)

    if collector["imap-logins"]:
        logger.add_heading("Recent IMAP Logins")
        logger.print_block("The most recent login from each remote IP adddress is show.")
        for k in utils.sort_email_addresses(collector["imap-logins"], env):
            for ip, date in sorted(collector["imap-logins"][k].items(), key=lambda kv: kv[1]):
                logger.print_line(k + "\t" + str(date) + "\t" + ip)

    if collector["postgrey"]:
        logger.add_heading("Greylisted Mail")
        logger.print_block("The following mail was greylisted, meaning the emails were temporarily rejected. Legitimate senders will try again within ten minutes.")
        logger.print_line("recipient" + "\t" + "received" + "\t" + "sender" + "\t" + "delivered")
        for recipient in utils.sort_email_addresses(collector["postgrey"], env):
            for (client_address, sender), (first_date, delivered_date) in sorted(collector["postgrey"][recipient].items(), key=lambda kv: kv[1][0]):
                logger.print_line(recipient + "\t" + str(first_date) + "\t" + sender + "\t" + (("delivered " + str(delivered_date)) if delivered_date else "no retry yet"))

    if collector["rejected-mail"]:
        logger.add_heading("Rejected Mail")
        logger.print_block("The following incoming mail was rejected.")
        for k in utils.sort_email_addresses(collector["rejected-mail"], env):
            for date, sender, message in collector["rejected-mail"][k]:
                logger.print_line(k + "\t" + str(date) + "\t" + sender + "\t" + message)

    if len(collector["other-services"]) > 0:
        logger.add_heading("Other")
        logger.print_block("Unrecognized services in the log: " + ", ".join(collector["other-services"]))


def scan_mail_log_line(line, collector):
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

    elif service in ("postfix/qmgr", "postfix/pickup", "postfix/cleanup",
                     "postfix/scache", "spampd", "postfix/anvil",
                     "postfix/master", "opendkim", "postfix/lmtp",
                     "postfix/tlsmgr"):
        # nothing to look at
        pass

    else:
        collector["other-services"].add(service)


def scan_dovecot_line(date, log, collector):
    m = re.match("imap-login: Login: user=<(.*?)>, method=PLAIN, rip=(.*?),", log)
    if m:
        login, ip = m.group(1), m.group(2)
        if ip != "127.0.0.1":  # local login from webmail/zpush
            collector["imap-logins"].setdefault(login, {})[ip] = date


def scan_postgrey_line(date, log, collector):
    m = re.match("action=(greylist|pass), reason=(.*?), (?:delay=\d+, )?client_name=(.*), client_address=(.*), sender=(.*), recipient=(.*)", log)
    if m:
        action, reason, client_name, client_address, sender, recipient = m.groups()
        key = (client_address, sender)
        if action == "greylist" and reason == "new":
            collector["postgrey"].setdefault(recipient, {})[key] = (date, None)
        elif action == "pass" and reason == "triplet found" and key in collector["postgrey"].get(recipient, {}):
            collector["postgrey"][recipient][key] = (collector["postgrey"][recipient][key][0], date)


def scan_postfix_smtpd_line(date, log, collector):
    m = re.match("NOQUEUE: reject: RCPT from .*?: (.*?); from=<(.*?)> to=<(.*?)>", log)
    if m:
        message, sender, recipient = m.groups()
        if recipient in collector["real_mail_addresses"]:
            # only log mail to real recipients

            # skip this, is reported in the greylisting report
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


if __name__ == "__main__":
    from status_checks import ConsoleOutput
    env = utils.load_environment()
    scan_mail_log(ConsoleOutput(), env)
