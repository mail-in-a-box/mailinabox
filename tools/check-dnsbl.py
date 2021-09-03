#!/usr/bin/env python3

# From https://github.com/gsauthof/utility Thanks!
# 2016, Georg Sauthoff <mail@georg.so>, GPLv3+

import argparse
import csv
# require dnspython >= 1.15
# because of: https://github.com/rthalley/dnspython/issues/206
import dns.resolver
import dns.reversename
import logging
import re
import sys
import time


default_blacklists = [
        ('zen.spamhaus.org'             , 'Spamhaus SBL, XBL and PBL'        ),
        ('dnsbl.sorbs.net'              , 'SORBS aggregated'                 ),
        ('safe.dnsbl.sorbs.net'         , "'safe' subset of SORBS aggregated"),
        ('ix.dnsbl.manitu.net'          , 'Heise iX NiX Spam'                ),
        ('truncate.gbudb.net'           , 'Exclusively Spam/Malware'         ),
        ('dnsbl-1.uceprotect.net'       , 'Trapserver Cluster'               ),
        ('cbl.abuseat.org'              , 'Net of traps'                     ),
        ('dnsbl.cobion.com'             , 'used in IBM products'             ),
        ('psbl.surriel.com'             , 'passive list, easy to unlist'     ),
        ('db.wpbl.info'                 , 'Weighted private'                 ),
        ('bl.spamcop.net'               , 'Based on spamcop users'           ),
        ('dyna.spamrats.com'            , 'Dynamic IP addresses'             ),
        ('spam.spamrats.com'            , 'Manual submissions'               ),
        ('auth.spamrats.com'            , 'Suspicious authentications'       ),
        ('dnsbl.inps.de'                , 'automated and reported'           ),
        ('bl.blocklist.de'              , 'fail2ban reports etc.'            ),
        ('all.s5h.net'                  , 'traps'                            ),
        ('rbl.realtimeblacklist.com'    , 'lists ip ranges'                  ),
        ('b.barracudacentral.org'       , 'traps'                            ),
        ('hostkarma.junkemailfilter.com', 'Autotected Virus Senders'         ),
        ('ubl.unsubscore.com'           , 'Collected Opt-Out Addresses'      ),
        ('0spam.fusionzero.com'         , 'Spam Trap'                        ),
        ('bl.nordspam.com'              , 'NordSpam IP addresses'            ),
        ('rbl.nordspam.com'             , 'NordSpam Domain list '            ),
        ('combined.mail.abusix.zone'    , 'Abusix aggregated'                ),
        ('black.dnsbl.brukalai.lt'      , 'Brukalai.lt junk mail'            ),
        ('light.dnsbl.brukalai.lt'      , 'Brukalai.lt abuse'                ),
        ]

# blacklists disabled by default because they return mostly garbage
garbage_blacklists = [
        # The spfbl.net operator doesn't publish clear criteria that lead to a
        # blacklisting.
        # When an IP address is blacklisted the operator can't name a specific
        # reason for the blacklisting. The blacklisting details page just names
        # overly generic reasons like:
        # 'This IP was flagged due to misconfiguration of the e-mail service or
        # the suspicion that there is no MTA at it.'
        # When contacting the operator's support, they can't back up such
        # claims.
        # There are additions of IP addresses to the spfbl.net blacklist that
        # have a properly configured MTA running and that aren't listed in any
        # other blacklist. Likely, those additions are caused by a bug in the
        # spfbl.net update process. But their support is uninterested in
        # improving that process. Instead they want to externalize maintenance
        # work by asking listed parties to waste some time on their manual
        # delisting process.
        # Suspiciously, you can even whitelist your listed address via
        # transferring $ 1.50 via PayPal. Go figure.
        # Thus, the value of querying this blacklist is utterly low as
        # you get false-positive results, very likely.
        ('dnsbl.spfbl.net'              , 'Reputation Database'              ),
        ]


# See also:
# https://en.wikipedia.org/wiki/DNSBL
# https://tools.ietf.org/html/rfc5782
# https://en.wikipedia.org/wiki/Comparison_of_DNS_blacklists

# some lists provide detailed stats, i.e. the actual listed addresses
# useful for testing


log_format      = '%(asctime)s - %(levelname)-8s - %(message)s [%(name)s]'
log_date_format = '%Y-%m-%d %H:%M:%S'

## Simple Setup

# Note that the basicConfig() call is a NOP in Jupyter
# because Jupyter calls it before
logging.basicConfig(format=log_format, datefmt=log_date_format, level=logging.WARNING)
log = logging.getLogger(__name__)



def mk_arg_parser():
    p = argparse.ArgumentParser(
            formatter_class=argparse.RawDescriptionHelpFormatter,
            description = 'Check if mailservers are in any blacklist (DNSBL)',
            epilog='''Don't panic if a server is listed in some blacklist.
See also https://en.wikipedia.org/wiki/Comparison_of_DNS_blacklists for the
mechanics and policies of the different lists.

2016, Georg Sauthoff <mail@georg.so>, GPLv3+''')
    p.add_argument('dests', metavar='DESTINATION', nargs='+',
            help = 'servers, a MX lookup is done if it is a domain')
    p.add_argument('--bl', action='append', default=[],
            help='add another blacklist')
    p.add_argument('--bl-file', help='read more DNSBL from a CSV file')
    p.add_argument('--clear', action='store_true',
            help='clear default list of DNSBL')
    # https://blog.cloudflare.com/dns-resolver-1-1-1-1/
    p.add_argument('--cloudflare', action='store_true',
            help="use Cloudflare's public DNS nameservers")
    p.add_argument('--debug', action='store_true',
            help='print debug log messages')
    # cf. https://en.wikipedia.org/wiki/Google_Public_DNS
    p.add_argument('--google', action='store_true',
            help="use Google's public DNS nameservers")
    p.add_argument('--rev', action='store_true', default=True,
            help='check reverse DNS record for each domain (default: on)')
    p.add_argument('--mx', action='store_true', default=True,
            help='try to folow MX entries')
    p.add_argument('--no-mx', dest='mx', action='store_false',
            help='ignore any MX records')
    p.add_argument('--no-rev', action='store_false', dest='rev',
            help='disable reverse DNS checking')
    p.add_argument('--ns', action='append', default=[],
            help='use one or more alternate nameserverse')
    # cf. https://en.wikipedia.org/wiki/OpenDNS
    p.add_argument('--opendns', action='store_true',
            help="use Cisco's public DNS nameservers")
    # cf. https://quad9.net/faq/
    p.add_argument('--quad9', action='store_true',
            help="use Quad9's public DNS nameservers (i.e. the filtering ones)")
    p.add_argument('--retries', type=int, default=5,
            help='Number of retries if request times out (default: 5)')
    p.add_argument('--with-garbage', action='store_true',
            help=('also include low-quality blacklists that are maintained'
            ' by clueless operators and thus easily return false-positives'))
    return p



def parse_args(*a):
    p = mk_arg_parser()
    args = p.parse_args(*a)
    args.bls = default_blacklists
    if args.clear:
        args.bls = []
    for bl in args.bl:
        args.bls.append((bl, ''))
    if args.bl_file:
        args.bls = args.bls + read_csv_bl(args.bl_file)
    if args.with_garbage:
        args.bls.extend(garbage_blacklists)
    if args.google:
        args.ns = args.ns + ['8.8.8.8', '2001:4860:4860::8888', '8.8.4.4', '2001:4860:4860::8844']
    if args.opendns:
        args.ns = args.ns + ['208.67.222.222', '2620:0:ccc::2', '208.67.220.220', '2620:0:ccd::2']
    if args.cloudflare:
        args.ns += ['1.1.1.1', '2606:4700:4700::1111', '1.0.0.1', '2606:4700:4700::1001']
    if args.quad9:
        args.ns += ['9.9.9.9', '2620:fe::fe', '149.112.112.112', '2620:fe::9']
    if args.ns:
        dns.resolver.default_resolver = dns.resolver.Resolver(configure=False)
        dns.resolver.default_resolver.nameservers = args.ns
    if args.debug:
        l = logging.getLogger() # root logger
        l.setLevel(logging.DEBUG)
    return args



def read_csv_bl(filename):
    with open(filename, newline='') as f:
        reader = csv.reader(f)
        xs = [ row for row in reader
                if len(row) > 0 and not row[0].startswith('#') ]
        return xs



v4_ex = re.compile('^[.0-9]+$')
v6_ex = re.compile('^[:0-9a-fA-F]+$')

def get_addrs(dest, mx=True):
    if v4_ex.match(dest) or v6_ex.match(dest):
        return [ (dest, None) ]
    domains = [ dest ]
    if mx:
        try:
            r = dns.resolver.resolve(dest, 'mx', search=True)
            domains = [ answer.exchange for answer in r ]
            log.debug('destinatin {} has MXs: {}'
                      .format(dest, ', '.join([str(d) for d in domains])))
        except dns.resolver.NoAnswer:
            pass
    addrs = []
    for domain in domains:
        for t in ['a', 'aaaa']:
            try:
                r = dns.resolver.resolve(domain, t, search=True)
            except dns.resolver.NoAnswer:
                continue
            xs = [ ( answer.address, domain ) for answer in r ]
            addrs = addrs + xs
            log.debug('domain {} has addresses: {}'
                      .format(domain, ', '.join([x[0] for x in xs])))
    if not addrs:
        raise ValueError("There isn't any a/aaaa DNS record for {}".format(domain))
    return addrs



def check_dnsbl(addr, bl):
    rev = dns.reversename.from_address(addr)
    domain = str(rev.split(3)[0]) + '.' + bl
    try:
        r = dns.resolver.resolve(domain, 'a', search=True)
    except (dns.resolver.NXDOMAIN, dns.resolver.NoNameservers, dns.resolver.NoAnswer):
        return 0
    address = list(r)[0].address
    try:
        r = dns.resolver.resolve(domain, 'txt', search=True)
        txt = list(r)[0].to_text()
    except (dns.resolver.NoAnswer, dns.resolver.NXDOMAIN):
        txt = ''
    log.error('OMG, {} is listed in DNSBL {}: {} ({})'.format(
        addr, bl, address, txt))
    return 1



def check_rdns(addrs):
    errs = 0
    for (addr, domain) in addrs:
        log.debug('Check if there is a reverse DNS record that maps address {} to {}'
                  .format(addr, domain))
        try:
            r = dns.resolver.resolve(dns.reversename.from_address(addr), 'ptr', search=True)
            a = list(r)[0]
            target = str(a.target).lower()
            source = str(domain).lower()
            log.debug('Reserve DNS record for {} points to {}'.format(addr, target))
            if domain and source + '.' != target and source != target:
                log.error('domain {} resolves to {}, but the reverse record resolves to {}'.
                         format(domain, addr, target))
                errs = errs + 1
        except (dns.resolver.NXDOMAIN, dns.resolver.NoAnswer):
            log.error('There is no reverse DNS record for {}'.format(addr))
            errs = errs + 1
            return errs
    return errs



def run(args):
    log.debug('Checking {} DNS blacklists'.format(args.bls.__len__()))
    errs = 0
    for dest in args.dests:
        addrs = get_addrs(dest, mx=args.mx)
        if args.rev:
            errs = errs + check_rdns(addrs)
        old_errs = errs
        ls = [ ( (x[0], x[1], y) for x in addrs for y in args.bls) ]
        i = 0
        while ls:
            ms = []
            for addr, domain, bl in ls[0]:
                log.debug('Checking if address {} (via {}) is listed in {} ({})'
                          .format(addr, dest, bl[0], bl[1]))
                try:
                    errs = errs + check_dnsbl(addr, bl[0])
                except dns.exception.Timeout as e:
                    m = 'Resolving  {}/{} in {} timed out: {}'.format(
                        addr, domain, bl[0], e)
                    if i >= args.retries:
                        log.warn(m)
                    else:
                        log.debug(m)
                        ms.append( (addr, domain, bl) )
            ls.pop(0)
            if ms and i + 1 < args.retries:
                ls.append(ms)
                log.debug('({}) Retrying {} timed-out entries'.format(i, len(ms)))
                time.sleep(23+i*23)
            i = i + 1
        if old_errs < errs:
            log.error('{} is listed in {} blacklists'.format(dest, errs - old_errs))
    return 0 if errs == 0 else 1



def main(*a):
    args = parse_args(*a)
    return run(args)



if __name__ == '__main__':
  if 'IPython' in sys.modules:
    # do something different when running inside a Jupyter notebook
    pass
  else:
    sys.exit(main())



##### Scratch area:
#
#
## In[ ]:
#
#check_rdns([('89.238.75.224', 'georg.so')])
#
#
## In[ ]:
#
#r = dns.resolver.resolve(dns.reversename.from_address('89.238.75.224'), 'ptr', search=True)
#a = list(r)[0]
#a.target.to_text()
#
#
## In[ ]:
#
#tr = dns.resolver.default_resolver 
#
#
## In[ ]:
#
#dns.resolver.default_resolver = dns.resolver.Resolver(configure=False)
## some DNSBLs might block public DNS servers (because of the volume) such that
## false-negatives are generated with them
## e.g. Google's Public DNS
#dns.resolver.default_resolver.nameservers = ['8.8.8.8', '2001:4860:4860::8888', '8.8.4.4', '2001:4860:4860::8844']
#
#
## In[ ]:
#
#dns.resolver.default_resolver = dns.resolver.Resolver(configure=False)
## OpenDNS
#dns.resolver.default_resolver.nameservers = ['208.67.222.222', '2620:0:ccc::2', '208.67.220.220', '2620:0:ccd::2']
#
#
## In[ ]:
#
#tr.nameservers
#
#
## In[ ]:
#
#dns.resolver.default_resolver = tr
#
#
## In[ ]:
#
#dns.__version__
#
#
## In[ ]:
#
## as of 2016-11, listed
#r = dns.resolver.resolve('39.227.103.116.zen.spamhaus.org', 'txt', search=True)
#answer = list(r)[0]
#answer.to_text()
#
#
## In[ ]:
#
#check_dnsbl('116.103.227.39', 'zen.spamhaus.org')
#
#
## In[ ]:
#
## as of 2016-11, not listed
#check_dnsbl('217.146.132.159', 'zen.spamhaus.org')
#
#
## In[ ]:
#
#get_addrs('georg.so')
#
#
## In[ ]:
#
#parse_args(['georg.so'])
#
#
## In[ ]:
#
#a = dns.resolver.resolve('georg.so', 'MX', search=True)
#
#
## In[ ]:
#
#print(dns.resolver.Resolver.query.__doc__)
#
#
## In[ ]:
#
#[ str(x.exchange) for x in a ]
#
#
## In[ ]:
#
#[ x.exchange for x in a]
#dns.resolver.resolve(list(a)[0].exchange, 'a', search=True)
#
#
## In[ ]:
#
#r = dns.reversename.from_address('89.238.75.224')
#str(r.split(3)[0])
#
#
## In[ ]:
#
## should throw NoAnswer
#a = dns.resolver.resolve('escher.lru.li', 'mx', search=True)
##b = list(a)
#a
#
#
## In[ ]:
#
#a = dns.resolver.resolve('georg.so', 'a', search=True)
#b = list(a)[0]
#b.address
#dns.reversename.from_address(b.address)
#
#
## In[ ]:
#
## should throw NXDOMAIN
#rs = str(r.split(3)[0])
#dns.resolver.resolve(rs + '.zen.spamhaus.org', 'A' , search=True)
#
#
## In[ ]:
#
#s = dns.reversename.from_address('2a00:1828:2000:164::12')
#str(s.split(3)[0])

