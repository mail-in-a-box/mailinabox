#!/usr/bin/python3
#
# This is a helper tool for editing configuration files during the setup
# process. The tool is given new values for settings as command-line
# arguments. It comments-out existing setting values in the configuration
# file and adds new values either after their former location or at the
# end.
#
# The configuration file has settings that look like:
#
# NAME=VALUE
#
# If the -s option is given, then space becomes the delimiter, i.e.:
#
# NAME VALUE
#
# If the -e option is given and VALUE is empty, the setting is removed
# from the configuration file if it is set (i.e. existing occurrences
# are commented out and no new setting is added).
#
# If the -c option is given, then the supplied character becomes the comment character
#
# If the -w option is given, then setting lines continue onto following
# lines while the lines start with whitespace, e.g.:
#
# NAME VAL
#   UE 

import sys, re

# sanity check
if len(sys.argv) < 3:
	print("usage: python3 editconf.py /etc/file.conf [-s] [-w] [-c <CHARACTER>] [-t] NAME=VAL [NAME=VAL ...]")
	sys.exit(1)

# parse command line arguments
filename = sys.argv[1]
settings = sys.argv[2:]

delimiter = "="
delimiter_re = r"\s*=\s*"
erase_setting = False
comment_char = "#"
folded_lines = False
testing = False
while settings[0][0] == "-" and settings[0] != "--":
	opt = settings.pop(0)
	if opt == "-s":
		# Space is the delimiter
		delimiter = " "
		delimiter_re = r"\s+"
	elif opt == "-e":
		# Erase settings that have empty values.
		erase_setting = True
	elif opt == "-w":
		# Line folding is possible in this file.
		folded_lines = True
	elif opt == "-c":
		# Specifies a different comment character.
		comment_char = settings.pop(0)
	elif opt == "-t":
		testing = True
	else:
		print("Invalid option.")
		sys.exit(1)

# sanity check command line
for setting in settings:
	try:
		name, value = setting.split("=", 1)
	except:
		import subprocess
		print("Invalid command line: ", subprocess.list2cmdline(sys.argv))

# create the new config file in memory

found = set()
buf = ""
input_lines = list(open(filename))

while len(input_lines) > 0:
	line = input_lines.pop(0)

	# If this configuration file uses folded lines, append any folded lines
	# into our input buffer.
	if folded_lines and line[0] not in (comment_char, " ", ""):
		while len(input_lines) > 0 and input_lines[0][0] in " \t":
			line += input_lines.pop(0)

	# See if this line is for any settings passed on the command line.
	for i in range(len(settings)):
		# Check if this line contain this setting from the command-line arguments.
		name, val = settings[i].split("=", 1)
		m = re.match(
			   "(\s*)"
			 + "(" + re.escape(comment_char) + "\s*)?"
			 + re.escape(name) + delimiter_re + "(.*?)\s*$",
			 line, re.S)
		if not m: continue
		indent, is_comment, existing_val = m.groups()

		# If this is already the setting, keep it in the file, except:
		# * If we've already seen it before, then remove this duplicate line.
		# * If val is empty and erase_setting is on, then comment it out.
		if is_comment is None and existing_val == val and not (not val and erase_setting):
			# It may be that we've already inserted this setting higher
			# in the file so check for that first.
			if i in found: break
			buf += line
			found.add(i)
			break
		
		# comment-out the existing line (also comment any folded lines)
		if is_comment is None:
			buf += comment_char + line.rstrip().replace("\n", "\n" + comment_char) + "\n"
		else:
			# the line is already commented, pass it through
			buf += line
		
		# if this option already is set don't add the setting again,
		# or if we're clearing the setting with -e, don't add it
		if (i in found) or (not val and erase_setting):
			break
		
		# add the new setting
		buf += indent + name + delimiter + val + "\n"
		
		# note that we've applied this option
		found.add(i)
		
		break
	else:
		# If did not match any setting names, pass this line through.
		buf += line
		
# Put any settings we didn't see at the end of the file,
# except settings being cleared.
for i in range(len(settings)):
	if i not in found:
		name, val = settings[i].split("=", 1)
		if not (not val and erase_setting):
			buf += name + delimiter + val + "\n"

if not testing:
	# Write out the new file.
	with open(filename, "w") as f:
		f.write(buf)
else:
	# Just print the new file to stdout.
	print(buf)
