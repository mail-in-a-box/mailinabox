#!/usr/bin/python3
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####

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
erase_setting_via_comment = True
comment_char = "#"
folded_lines = False
testing = False
ini_section = None
case_insensitive_names = False
case_insensitive_values = False
while settings[0][0] == "-" and settings[0] != "--":
	opt = settings.pop(0)
	if opt == "-s":
		# Space is the delimiter
		delimiter = " "
		delimiter_re = r"\s+"
	elif opt == "-e":
		# Erase settings that have empty values.
		erase_setting = True
	elif opt == "-E":
		# Erase settings (remove from file) that have empty values.
		erase_setting = True
		erase_setting_via_comment = False
	elif opt == "-w":
		# Line folding is possible in this file.
		folded_lines = True
	elif opt == "-c":
		# Specifies a different comment character.
		comment_char = settings.pop(0)
	elif opt == "-ini-section":
		ini_section = settings.pop(0)
	elif opt == "-case-insensitive":
		case_insensitive_names = True
		case_insensitive_values = True
	elif opt == "-t":
		testing = True
	else:
		print("Invalid option.")
		sys.exit(1)

class Setting(object):
	def __init__(self, setting):
		self.name, self.val = setting.split("=", 1)
                # add_only: do not modify existing value
		self.add_only = self.name.startswith("+")
		if self.add_only: self.name=self.name[1:]
	def val_eq(self, other_val, case_insensitive):
		if not case_insensitive:
			r = self.val == other_val
		else:
			r = self.val.lower() == other_val.lower()
		return r
# sanity check command line
try:
	settings = [ Setting(x) for x in settings ]
except:
	import subprocess
	print("Invalid command line: ", subprocess.list2cmdline(sys.argv))


# create the new config file in memory

found = set()
buf = ""
input_lines = list(open(filename))
cur_section = None

while len(input_lines) > 0:
	line = input_lines.pop(0)

	# If this configuration file uses folded lines, append any folded lines
	# into our input buffer.
	if folded_lines and line[0] not in (comment_char, " ", ""):
		while len(input_lines) > 0 and input_lines[0][0] in " \t":
			line += input_lines.pop(0)

	# If an ini file, keep track of what section we're in
	if ini_section and line.startswith('[') and line.strip().endswith(']'):
		if cur_section == ini_section.lower():
			# Put any settings we didn't see at the end of the section.
			for i in range(len(settings)):
				if i not in found:
					name, val = (settings[i].name, settings[i].val)
					if not (not val and erase_setting):
					        buf += name + delimiter + val + "\n"
		cur_section = line.strip()[1:-1].strip().lower()
		buf += line
		continue

	if ini_section and cur_section != ini_section.lower():
		# we're not processing the desired section, just append
		buf += line
		continue

	# See if this line is for any settings passed on the command line.
	for i in range(len(settings)):
		# Check if this line contain this setting from the command-line arguments.
		name, val = (settings[i].name, settings[i].val)
		flags = re.S | (re.I if case_insensitive_names else 0)
		m = re.match(
			   "(\s*)"
			 + "(" + re.escape(comment_char) + "\s*)?"
			 + re.escape(name) + delimiter_re + "(.*?)\s*$",
			 line, flags)
		if not m: continue
		indent, is_comment, existing_val = m.groups()

                # With + before the name, don't modify the existing value
		if settings[i].add_only:
			found.add(i)
			buf += line
			break

		# If this is already the setting, keep it in the file, except:
		# * If we've already seen it before, then remove this duplicate line.
		# * If val is empty and erase_setting is on, then comment it out.
		if is_comment is None and settings[i].val_eq(existing_val, case_insensitive_values) and not (not val and erase_setting):
			# It may be that we've already inserted this setting higher
			# in the file so check for that first.
			if i in found: break
			buf += line
			found.add(i)
			break
		
		# comment-out the existing line (also comment any folded lines)
		if is_comment is None:
			if val or not erase_setting or erase_setting_via_comment:
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
if not ini_section or cur_section == ini_section.lower():
	for i in range(len(settings)):
		if (i not in found):
			name, val = (settings[i].name, settings[i].val)
			if not (not val and erase_setting):
				buf += name + delimiter + val + "\n"

if not testing:
	# Write out the new file.
	with open(filename, "w") as f:
		f.write(buf)
else:
	# Just print the new file to stdout.
	print(buf)
