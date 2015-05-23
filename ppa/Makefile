all:
	# Clean.
	rm -rf /tmp/build

	# Prepare to build source packages.
	sudo apt-get install -y git dpkg-dev devscripts dput
	mkdir -p /tmp/build

	# POSTGREY

	# Download our fork of the Debian postgrey package.
	git clone https://github.com/mail-in-a-box/postgrey /tmp/build/postgrey

	# Download the corresponding upstream package.
	wget -O /tmp/build/postgrey_1.35.orig.tar.gz http://postgrey.schweikert.ch/pub/postgrey-1.35.tar.gz

	# Build the source package.
	sudo apt-get build-dep -y postgrey
	(cd /tmp/build/postgrey; dpkg-source -b .)
	(cd /tmp/build/postgrey; dpkg-buildpackage -S -us -uc -nc)

	# Sign the packages.
	debsign /tmp/build/postgrey_1.35-1miab1_source.changes

	# Upload to PPA.
	dput ppa:mail-in-a-box/ppa /tmp/build/postgrey_1.35-1miab1_source.changes

	# Clear the intermediate files.
	rm -rf /tmp/build/postgrey

