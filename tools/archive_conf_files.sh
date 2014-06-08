# Use this script to make an archive of the contents of all
# of the configuration files we edit with editconf.py.
for fn in `grep -hr editconf.py setup | sed "s/tools\/editconf.py //" | sed "s/ .*//" | sort | uniq`; do
	echo ======================================================================
	echo $fn
	echo ======================================================================
	cat $fn
done

