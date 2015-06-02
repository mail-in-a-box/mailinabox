POSTGREY_VERSION=1.35-1+miab1

all: clean build_postgrey build_dovecot_lucene

clean:
	# Clean.
	rm -rf /tmp/build

	# Prepare to build source packages.
	mkdir -p /tmp/build

build_postgrey: clean
	# Download the latest Debian postgrey package. It is ahead of Ubuntu,
	# and we might as well jump ahead.
	git clone git://git.debian.org/git/collab-maint/postgrey.git /tmp/build/postgrey

	# Download the corresponding upstream package.
	wget -O /tmp/build/postgrey_1.35.orig.tar.gz http://postgrey.schweikert.ch/pub/postgrey-1.35.tar.gz

	# Add our source patch to the debian packaging listing.
	cp postgrey_sources.diff /tmp/build/postgrey/debian/patches/mailinabox

	# Patch the packaging to give it a new version.
	patch -p1 -d /tmp/build/postgrey < postgrey.diff

	# Build the source package.
	(cd /tmp/build/postgrey; dpkg-buildpackage -S -us -uc -nc)

	# Sign the packages.
	debsign /tmp/build/postgrey_$(POSTGREY_VERSION)_source.changes

	# Upload to PPA.
	dput ppa:mail-in-a-box/ppa /tmp/build/postgrey_$(POSTGREY_VERSION)_source.changes

	# Clear the intermediate files.
	rm -rf /tmp/build/postgrey

	# TESTING BINARY PACKAGE
	#sudo apt-get build-dep -y postgrey
	#(cd /tmp/build/postgrey; dpkg-buildpackage -us -uc -nc)

build_dovecot_lucene: clean
	# Get the upstream source.
	(cd /tmp/build; apt-get source dovecot)

	# Patch it so that we build dovecot-lucene (and nothing else).
	patch -p1 -d /tmp/build/dovecot-2.2.9 < dovecot_lucene.diff

	# Build the source package.
	(cd /tmp/build/dovecot-2.2.9; dpkg-buildpackage -S -us -uc -nc)

	# Sign the packages.
	#debsign /tmp/build/dovecot_2.2.9-1ubuntu2.1_amd64.changes

	# Upload it.
	#dput ppa:mail-in-a-box/ppa /tmp/build/dovecot_2.2.9-1ubuntu2.1_amd64.changes

	# TESTING BINARY PACKAGE
	# Install build dependencies and build dependencies we've added in our patch,
	# and then build the binary package.
	#sudo apt-get build-dep -y dovecot
	#sudo apt-get install libclucene-dev liblzma-dev libexttextcat-dev libstemmer-dev
	#(cd /tmp/build/dovecot-2.2.9; dpkg-buildpackage -us -uc -nc)
