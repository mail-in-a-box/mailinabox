def load_env_vars_from_file(fn):
    # Load settings from a KEY=VALUE file.
    env = {}
    for line in open(fn):
        env.setdefault(*line.strip().split("=", 1))
    # strip_quotes:
    for k in env: env[k]=env[k].strip('"')
    return env

