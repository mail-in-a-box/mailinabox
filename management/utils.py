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

def save_environment(env):
    with open("/etc/mailinabox.conf", "w") as f:
        for k, v in env.items():
            f.write("%s=%s\n" % (k, v))

def safe_domain_name(name):
    # Sanitize a domain name so it is safe to use as a file name on disk.
    import urllib.parse
    return urllib.parse.quote(name, safe='')

def sort_domains(domain_names, env):
    # Put domain names in a nice sorted order. For web_update, PRIMARY_HOSTNAME
    # must appear first so it becomes the nginx default server.
    
    # First group PRIMARY_HOSTNAME and its subdomains, then parent domains of PRIMARY_HOSTNAME, then other domains.
    groups = ( [], [], [] )
    for d in domain_names:
        if d == env['PRIMARY_HOSTNAME'] or d.endswith("." + env['PRIMARY_HOSTNAME']):
            groups[0].append(d)
        elif env['PRIMARY_HOSTNAME'].endswith("." + d):
            groups[1].append(d)
        else:
            groups[2].append(d)

    # Within each group, sort parent domains before subdomains and after that sort lexicographically.
    def sort_group(group):
        # Find the top-most domains.
        top_domains = sorted(d for d in group if len([s for s in group if d.endswith("." + s)]) == 0)
        ret = []
        for d in top_domains:
            ret.append(d)
            ret.extend( sort_group([s for s in group if s.endswith("." + d)]) )
        return ret
        
    groups = [sort_group(g) for g in groups]

    return groups[0] + groups[1] + groups[2]

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
