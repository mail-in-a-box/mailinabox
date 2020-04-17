#!/usr/bin/python3

from os import system, argv

# Pass control to the actual script
system(f"management/editconf.py {argv[1:]}")
