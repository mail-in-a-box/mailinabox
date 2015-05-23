all: clean build_postgrey build_dovecot_lucene

clean:
	# Clean.
	rm -rf /tmp/build

	# Prepare to build source packages.
	mkdir -p /tmp/build

build_postgrey:
	# Download our fork of the Debian postgrey package.
	git clone https://github.com/mail-in-a-box/postgrey /tmp/build/postgrey

	# Download the corresponding upstream package.
	wget -O /tmp/build/postgrey_1.35.orig.tar.gz http://postgrey.schweikert.ch/pub/postgrey-1.35.tar.gz

	# Build the source package.
	(cd /tmp/build/postgrey; dpkg-buildpackage -S -us -uc -nc)

	# Sign the packages.
	debsign /tmp/build/postgrey_1.35-1miab1_source.changes

	# Upload to PPA.
	dput ppa:mail-in-a-box/ppa /tmp/build/postgrey_1.35-1miab1_source.changes

	# Clear the intermediate files.
	rm -rf /tmp/build/postgrey

	# TESTING BINARY PACKAGE
	#sudo apt-get build-dep -y postgrey
	#(cd /tmp/build/postgrey; dpkg-buildpackage -us -uc -nc)

build_dovecot_lucene:
	# Get the upstream source.
	(cd /tmp/build; apt-get source dovecot)

	# Patch it so that we build dovecot-lucene (and nothing else).
	patch -p1 -d /tmp/build/dovecot-2.2.9 < dovecot_lucene.diff

	# Build the source package.
	(cd /tmp/build/dovecot-2.2.9; dpkg-buildpackage -S -us -uc -nc)

	# Sign the packages.
	debsign /tmp/build/dovecot_2.2.9-1ubuntu2.2~ppa0~trusty0_source.changes

	# Upload it.
	dput ppa:mail-in-a-box/ppa /tmp/build/dovecot_2.2.9-1ubuntu2.2~ppa0~trusty0_source.changes

	# TESTING BINARY PACKAGE
	# Install build dependencies and build dependencies we've added in our patch,
	# and then build the binary package.
	#sudo apt-get build-dep -y dovecot
	#sudo apt-get install libclucene-dev liblzma-dev libexttextcat-dev libstemmer-dev
	#(cd /tmp/build/dovecot-2.2.9; dpkg-buildpackage -us -uc -nc)
