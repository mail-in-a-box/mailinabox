import os.path, idna, sys, collections

def get_www_domains(domains_to_skip):
    # Returns the domain names (IDNA-encoded) of all of the domains that are configured to serve www
    # on the system. 
    domains = []

    try:
        # read a line from text file
        with open("/etc/miabwwwdomains.conf") as file_in:
            for line in file_in:
                # Valid domain check future extention: use validators module
                # Only one dot allowed
                if line.count('.') == 1:
                    www_domain = get_domain(line, as_unicode=False)
                    if www_domain not in domains_to_skip:
                        domains.append(www_domain)
    except:
        # ignore failures
        pass
    
    return set(domains)


def get_domain(domaintxt, as_unicode=True):
    ret = domaintxt.rstrip()
    if as_unicode:
        try:
            ret = idna.decode(ret.encode('ascii'))
        except (ValueError, UnicodeError, idna.IDNAError):
            pass

    return ret

