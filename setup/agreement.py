import sys
import rtyaml
import collections
import os.path

def load_environment():
	# Load settings from a KEY=VALUE file.
    import collections
    env = collections.OrderedDict()
    for line in open("/etc/mailinabox.conf"): env.setdefault(*line.strip().split("=", 1))
    return env

def write_settings(config, env):
    fn = sys.argv[2]
    with open(fn, "w") as f:
        f.write(rtyaml.dump(config))

def load_settings(env):
    fn = sys.argv[2]
    try:
        config = rtyaml.load(open(fn, "r"))
        if not isinstance(config, dict): raise ValueError() # caught below
        return config
    except:
        return { }

env = load_environment()

if(sys.argv[2]):

	if( sys.argv[1] == "check" ):
		yaml = rtyaml.load(open( sys.argv[2] ))

		if( yaml.get("mailinabox-agreement", True) ):
			print("true")
		else:
			print("false")


	elif( sys.argv[1] == "set" ):
		config = load_settings(env)

		config["mailinabox-agreement"] = True
		write_settings( config, env )