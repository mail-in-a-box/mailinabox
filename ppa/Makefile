all:
	# Clean.
	rm -rf build

	# Prepare to build source packages.
	sudo apt-get install -y git dpkg-dev devscripts dput
	mkdir -p build

	# POSTGREY

	# Download our fork of the Debian postgrey package.
	git clone https://github.com/mail-in-a-box/postgrey build/postgrey

	# Download the corresponding upstream package.
	wget -O build/postgrey_1.35.orig.tar.gz http://postgrey.schweikert.ch/pub/postgrey-1.35.tar.gz

	# Build the source package.
	sudo apt-get build-dep -y postgrey
	(cd build/postgrey; dpkg-source -b .)
	(cd build/postgrey; dpkg-buildpackage -S -us -uc -nc)

	# Sign the packages.
	debsign build/postgrey_1.35-1miab1_source.changes

	# Upload to PPA.
	dput ppa:mail-in-a-box/ppa build/postgrey_1.35-1miab1_source.changes

	# Clear the intermediate files.
	rm -rf build/postgrey

