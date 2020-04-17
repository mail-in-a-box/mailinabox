#!/usr/bin/python3

from os import system
from sys import argv

# Pass control to the actual script
system(f"management/editconf.py {' '.join(str(x) for x in argv[1:])}")
