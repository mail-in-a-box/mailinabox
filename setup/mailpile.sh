#!/bin/bash

# Install Mailpile (https://www.mailpile.is/), a new
# modern webmail client currently in alpha.

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

# Dependencies, via their Makefile's debian-dev target and things they
# should have also mentioned.

apt_install python-imaging python-lxml python-jinja2 pep8 \
	ruby-dev yui-compressor python-nose spambayes \
	phantomjs python-pip python-mock python-pgpdump
pip install 'selenium>=2.40.0'
gem install therubyracer less

# Install Mailpile

# TODO: Install from a release.
if [ ! -d externals/Mailpile ]; then
	mkdir -p externals
	git clone https://github.com/pagekite/Mailpile.git externals/Mailpile
fi
