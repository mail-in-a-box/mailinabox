#!/usr/bin/python3

import sys, re

# sanity check
if len(sys.argv) < 3:
	print("usage: python3 editconf.py /etc/file.conf NAME=VAL [NAME=VAL ...]")
	sys.exit(1)

# parse command line arguments
filename = sys.argv[1]
settings = sys.argv[2:]

# create the new config file in memory
found = set()
buf = ""
for line in open(filename):
	for i in range(len(settings)):
		name, val = settings[i].split("=", 1)
		if re.match("\s*" + re.escape(name) + "\s*=", line):
			buf += "#" + line
			if i in found: break # we've already set the directive
			buf += name + "=" + val + "\n"
			found.add(i)
			break
	else:
		# did not match any setting name
		buf += line
		
for i in range(len(settings)):
	if i not in found:
		buf += settings[i] + "\n"

# Write out the new file.
with open(filename, "w") as f:
	f.write(buf)
	
