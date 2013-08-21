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
		m = re.match("\s*" + re.escape(name) + "\s*=\s*(.*?)\s*$", line)
		if m:
			# If this is already the setting, do nothing.
			if m.group(1) == val:
				buf += line
				found.add(i)
				break
			
			# comment-out the existing line
			buf += "#" + line
			
			# if this option oddly appears more than once, don't add the settingg again
			if i in found:
				break
			
			# add the new setting
			buf += name + "=" + val + "\n"
			
			# note that we've applied this option
			found.add(i)
			
			break
	else:
		# If did not match any setting names, pass this line through.
		buf += line
		
# Put any settings we didn't see at the end of the file.
for i in range(len(settings)):
	if i not in found:
		buf += settings[i] + "\n"

# Write out the new file.
with open(filename, "w") as f:
	f.write(buf)
	
