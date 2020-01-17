# -*- indent-tabs-mode: nil; -*-
import os.path, collections

# DO NOT import non-standard modules. This module is imported by
# migrate.py which runs on fresh machines before anything is installed
# besides Python.

# THE ENVIRONMENT FILE AT /etc/mailinabox.conf

class Environment(collections.OrderedDict):
    # subclass OrderedDict and provide attribute lookups to the
    # underlying dictionary
    def __getattr__(self, attr):
        return self[attr]

def load_environment():
    # Load settings from /etc/mailinabox.conf.
    env = load_env_vars_from_file("/etc/mailinabox.conf")

    # Load settings from STORAGE_ROOT/ldap/miab_ldap.conf
    # It won't exist exist until migration 13 completes...
    if os.path.exists(os.path.join(env["STORAGE_ROOT"],"ldap/miab_ldap.conf")):
        load_env_vars_from_file(os.path.join(env["STORAGE_ROOT"],"ldap/miab_ldap.conf"), strip_quotes=True, merge_env=env)
    
    return env

def load_env_vars_from_file(fn, strip_quotes=False, merge_env=None):
    # Load settings from a KEY=VALUE file.
    env = Environment()
    for line in open(fn):
        env.setdefault(*line.strip().split("=", 1))
    if strip_quotes:
        for k in env: env[k]=env[k].strip('"')
    if merge_env is not None:
        for k in env: merge_env[k]=env[k]
    return env

def save_environment(env):
    with open("/etc/mailinabox.conf", "w") as f:
        for k, v in env.items():
            f.write("%s=%s\n" % (k, v))

# THE SETTINGS FILE AT STORAGE_ROOT/settings.yaml.

def write_settings(config, env):
    import rtyaml
    fn = os.path.join(env['STORAGE_ROOT'], 'settings.yaml')
    with open(fn, "w") as f:
        f.write(rtyaml.dump(config))

def load_settings(env):
    import rtyaml
    fn = os.path.join(env['STORAGE_ROOT'], 'settings.yaml')
    try:
        config = rtyaml.load(open(fn, "r"))
        if not isinstance(config, dict): raise ValueError() # caught below
        return config
    except:
        return { }

# UTILITIES

def safe_domain_name(name):
    # Sanitize a domain name so it is safe to use as a file name on disk.
    import urllib.parse
    return urllib.parse.quote(name, safe='')

def sort_domains(domain_names, env):
    # Put domain names in a nice sorted order.

    # The nice order will group domain names by DNS zone, i.e. the top-most
    # domain name that we serve that ecompasses a set of subdomains. Map
    # each of the domain names to the zone that contains them. Walk the domains
    # from shortest to longest since zones are always shorter than their
    # subdomains.
    zones = { }
    for domain in sorted(domain_names, key=lambda d : len(d)):
        for z in zones.values():
            if domain.endswith("." + z):
                # We found a parent domain already in the list.
                zones[domain] = z
                break
        else:
            # 'break' did not occur: there is no parent domain, so it is its
            # own zone.
            zones[domain] = domain

    # Sort the zones.
    zone_domains = sorted(zones.values(),
      key = lambda d : (
        # PRIMARY_HOSTNAME or the zone that contains it is always first.
        not (d == env['PRIMARY_HOSTNAME'] or env['PRIMARY_HOSTNAME'].endswith("." + d)),

        # Then just dumb lexicographically.
        d,
      ))

    # Now sort the domain names that fall within each zone.
    domain_names = sorted(domain_names,
      key = lambda d : (
        # First by zone.
        zone_domains.index(zones[d]),

        # PRIMARY_HOSTNAME is always first within the zone that contains it.
        d != env['PRIMARY_HOSTNAME'],

        # Followed by any of its subdomains.
        not d.endswith("." + env['PRIMARY_HOSTNAME']),

        # Then in right-to-left lexicographic order of the .-separated parts of the name.
        list(reversed(d.split("."))),
      ))
    
    return domain_names

def sort_email_addresses(email_addresses, env):
    email_addresses = set(email_addresses)
    domains = set(email.split("@", 1)[1] for email in email_addresses if "@" in email)
    ret = []
    for domain in sort_domains(domains, env):
        domain_emails = set(email for email in email_addresses if email.endswith("@" + domain))
        ret.extend(sorted(domain_emails))
        email_addresses -= domain_emails
    ret.extend(sorted(email_addresses)) # whatever is left
    return ret

def shell(method, cmd_args, env={}, capture_stderr=False, return_bytes=False, trap=False, input=None):
    # A safe way to execute processes.
    # Some processes like apt-get require being given a sane PATH.
    import subprocess

    env.update({ "PATH": "/sbin:/bin:/usr/sbin:/usr/bin" })
    kwargs = {
        'env': env,
        'stderr': None if not capture_stderr else subprocess.STDOUT,
    }
    if method == "check_output" and input is not None:
        kwargs['input'] = input

    if not trap:
        ret = getattr(subprocess, method)(cmd_args, **kwargs)
    else:
        try:
            ret = getattr(subprocess, method)(cmd_args, **kwargs)
            code = 0
        except subprocess.CalledProcessError as e:
            ret = e.output
            code = e.returncode
    if not return_bytes and isinstance(ret, bytes): ret = ret.decode("utf8")
    if not trap:
        return ret
    else:
        return code, ret

def create_syslog_handler():
    import logging.handlers
    handler = logging.handlers.SysLogHandler(address='/dev/log')
    handler.setLevel(logging.WARNING)
    return handler

def du(path):
    # Computes the size of all files in the path, like the `du` command.
    # Based on http://stackoverflow.com/a/17936789. Takes into account
    # soft and hard links.
    total_size = 0
    seen = set()
    for dirpath, dirnames, filenames in os.walk(path):
        for f in filenames:
            fp = os.path.join(dirpath, f)
            try:
                stat = os.lstat(fp)
            except OSError:
                continue
            if stat.st_ino in seen:
                continue
            seen.add(stat.st_ino)
            total_size += stat.st_size
    return total_size

def wait_for_service(port, public, env, timeout):
	# Block until a service on a given port (bound privately or publicly)
	# is taking connections, with a maximum timeout.
	import socket, time
	start = time.perf_counter()
	while True:
		s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
		s.settimeout(timeout/3)
		try:
			s.connect(("127.0.0.1" if not public else env['PUBLIC_IP'], port))
			return True
		except OSError:
			if time.perf_counter() > start+timeout:
				return False
		time.sleep(min(timeout/4, 1))

def fix_boto():
	# Google Compute Engine instances install some Python-2-only boto plugins that
	# conflict with boto running under Python 3. Disable boto's default configuration
	# file prior to importing boto so that GCE's plugin is not loaded:
	import os
	os.environ["BOTO_CONFIG"] = "/etc/boto3.cfg"


if __name__ == "__main__":
	from web_update import get_web_domains
	env = load_environment()
	domains = get_web_domains(env)
	for domain in domains:
		print(domain)
