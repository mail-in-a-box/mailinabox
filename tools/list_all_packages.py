#!/usr/bin/python3

import os.path, glob, re

packages = set()

def add(line):
	global packages
	if line.endswith("\\"): line = line[:-1]
	packages |= set(p for p in line.split(" ") if p not in("", "apt_install"))

for fn in glob.glob(os.path.join(os.path.dirname(__file__), "../setup/*.sh")):
	with open(fn) as f:
		in_apt_install = False
		for line in f:
			line = line.strip()
			if line.startswith("apt_install "):
				in_apt_install = True
			if in_apt_install:
				add(line)
			in_apt_install = in_apt_install and line.endswith("\\")

print("\n".join(sorted(packages)))
