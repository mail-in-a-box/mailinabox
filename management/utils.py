import os.path

CONF_DIR = os.path.join(os.path.dirname(__file__), "../conf")

def load_environment():
    # Load settings from /etc/mailinabox.conf.
    return load_env_vars_from_file("/etc/mailinabox.conf")

def load_env_vars_from_file(fn):
    # Load settings from a KEY=VALUE file.
    import collections
    env = collections.OrderedDict()
    for line in open(fn): env.setdefault(*line.strip().split("=", 1))
    return env

# Settings
settings_root = os.path.join(load_environment()["STORAGE_ROOT"], '/')
default_settings = {
	"PRIVACY": 'TRUE'
}

def write_settings(newconfig):
	with open(os.path.join(settings_root, 'settings.yaml'), "w") as f:
		f.write(rtyaml.dump(newconfig))

def load_settings():
    try:
        config = rtyaml.load(open(os.path.join(settings_root, 'settings.yaml'), "w"))
        if not isinstance(config, dict): raise ValueError() # caught below
    except:
        return default_settings

        merged_config = default_settings.copy()
        merged_config.update(config)

        return config

def save_environment(env):
    with open("/etc/mailinabox.conf", "w") as f:
        for k, v in env.items():
            f.write("%s=%s\n" % (k, v))

def write_settings(env):
    with open(os.path.join(settings_root, 'settings.yaml'), "w") as f:
        f.write(rtyaml.dump(newconfig))

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

def exclusive_process(name):
    # Ensure that a process named `name` does not execute multiple
    # times concurrently.
    import os, sys, atexit
    pidfile = '/var/run/mailinabox-%s.pid' % name
    mypid = os.getpid()

    # Attempt to get a lock on ourself so that the concurrency check
    # itself is not executed in parallel.
    with open(__file__, 'r+') as flock:
        # Try to get a lock. This blocks until a lock is acquired. The
        # lock is held until the flock file is closed at the end of the
        # with block.
        os.lockf(flock.fileno(), os.F_LOCK, 0)

        # While we have a lock, look at the pid file. First attempt
        # to write our pid to a pidfile if no file already exists there.
        try:
            with open(pidfile, 'x') as f:
                # Successfully opened a new file. Since the file is new
                # there is no concurrent process. Write our pid.
                f.write(str(mypid))
                atexit.register(clear_my_pid, pidfile)
                return
        except FileExistsError:
            # The pid file already exixts, but it may contain a stale
            # pid of a terminated process.
            with open(pidfile, 'r+') as f:
                # Read the pid in the file.
                existing_pid = None
                try:
                    existing_pid = int(f.read().strip())
                except ValueError:
                    pass # No valid integer in the file.

                # Check if the pid in it is valid.
                if existing_pid:
                    if is_pid_valid(existing_pid):
                        print("Another %s is already running (pid %d)." % (name, existing_pid), file=sys.stderr)
                        sys.exit(1)

                # Write our pid.
                f.seek(0)
                f.write(str(mypid))
                f.truncate()
                atexit.register(clear_my_pid, pidfile)


def clear_my_pid(pidfile):
    import os
    os.unlink(pidfile)


def is_pid_valid(pid):
    """Checks whether a pid is a valid process ID of a currently running process."""
    # adapted from http://stackoverflow.com/questions/568271/how-to-check-if-there-exists-a-process-with-a-given-pid
    import os, errno
    if pid <= 0: raise ValueError('Invalid PID.')
    try:
        os.kill(pid, 0)
    except OSError as err:
        if err.errno == errno.ESRCH: # No such process
            return False
        elif err.errno == errno.EPERM: # Not permitted to send signal
            return True
        else: # EINVAL
            raise
    else:
        return True

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

if __name__ == "__main__":
	from dns_update import get_dns_domains
	from web_update import get_web_domains, get_default_www_redirects
	env = load_environment()
	domains = get_dns_domains(env) | set(get_web_domains(env) + get_default_www_redirects(env))
	domains = sort_domains(domains, env)
	for domain in domains:
		print(domain)
