ipsets-persistent
=================

init.d script for iptables-persistent on Debian/Ubuntu that also saves/loads ipsets


I added checking for and saving ipsets. sets are saved in the same place as the other rules in a file named rules.ipset. Rules are only saved if they are defined, same with flushing and loading. Instead of checking to see if ipset is installed on the load, I just check for the rules.ipset file, since if that doesn't exist loading does't make sense. There might be better ways to do it, feel free to submit a pull etc. this is just the way I made it work for me.
