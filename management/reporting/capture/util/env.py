#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####

def load_env_vars_from_file(fn):
    # Load settings from a KEY=VALUE file.
    env = {}
    for line in open(fn):
        env.setdefault(*line.strip().split("=", 1))
    # strip_quotes:
    for k in env: env[k]=env[k].strip('"')
    return env

