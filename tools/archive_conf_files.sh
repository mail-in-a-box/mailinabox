#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####

# Use this script to make an archive of the contents of all
# of the configuration files we edit with editconf.py.
for fn in `grep -hr editconf.py setup | sed "s/tools\/editconf.py //" | sed "s/ .*//" | sort | uniq`; do
	echo ======================================================================
	echo $fn
	echo ======================================================================
	cat $fn
done

