ppa instructions
================

Mail-in-a-Box maintains a Launchpad.net PPA ([Mail-in-a-Box PPA](https://launchpad.net/~mail-in-a-box/+archive/ubuntu/ppa)) for additional deb's that we want to have installed on systems.

Packages
--------

* [postgrey](https://github.com/mail-in-a-box/postgrey), with a modification to whitelist senders that are whitelisted by [dnswl.org](https://www.dnswl.org/) (i.e. don't greylist mail from them).

Building
--------

To rebuild the packages in the PPA, you'll need to be @JoshData.

First:

* You should have an account on Launchpad.net.
* Your account should have your GPG key set (to the fingerprint of a GPG key on your system matching the identity at the top of the debian/changelog files).
* You should have write permission to the PPA.

To build:

	# Start a clean VM.
	vagrant up

	# Put your signing keys (on the host machine) into the VM (so it can sign the debs).
	gpg --export-secret-keys | vagrant ssh -- gpg --import

	# Build & upload to launchpad.
	vagrant ssh -- "cd /vagrant && make"

To use on a Mail-in-a-Box box, add the PPA and then upgrade packages:

	apt-add-repository ppa:mail-in-a-box/ppa
	apt-get update
	apt-get upgrade

