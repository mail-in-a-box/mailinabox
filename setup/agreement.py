# This script deals with the Mail-in-a-Box configuration
# (usually located at /home/user-data/settings.yaml)
# to see if the user has agreed to Mail-in-a-Box.
# This script can either check, or write in the configuration
# that the user has agreed.

#usage: python setup/agreement.py [set, check] [YAML file]
#example: python setup/agreement.py set /home/user-data/settings.yaml
#    prints: (nothing)
#example: python setyp/agreement.py check /home/user-data/settings.yaml
#    prints: "true" or "false"


import sys
import rtyaml
import collections

def write_settings(config):
    fn = sys.argv[2]
    with open(fn, "w") as f:
        f.write(rtyaml.dump(config))

def load_settings():
    fn = sys.argv[2]
    try:
        config = rtyaml.load(open(fn, "r"))
        if not isinstance(config, dict): raise ValueError() # caught below
        return config
    except:
        return { }

if(sys.argv[2]):

	if( sys.argv[1] == "check" ):
		yaml = rtyaml.load(open( sys.argv[2] ))

		if( yaml.get("mailinabox-agreement", True) ):
			print("true")
		else:
			print("false")


	elif( sys.argv[1] == "set" ):
		config = load_settings()

		config["mailinabox-agreement"] = True
		write_settings( config )