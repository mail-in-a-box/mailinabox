# Contributing

Mail-in-a-Box is an open source project. Your contributions and pull requests are welcome.

## Development

To start developing Mail-in-a-Box, [clone the repository](https://github.com/mail-in-a-box/mailinabox) and familiarize yourself with the code. Then move to the cloned mailinabox directory.

    $ git clone https://github.com/mail-in-a-box/mailinabox
	$ cd mailinabox

### Vagrant and VirtualBox

We recommend you use [Vagrant](https://www.vagrantup.com/intro/getting-started/install.html) and [VirtualBox](https://www.virtualbox.org/wiki/Downloads) for development. Please install them first.

With Vagrant set up, the following should boot up Mail-in-a-Box inside a virtual machine:

    $ vagrant up --provision



### Modifying your `hosts` file

After a while, Mail-in-a-Box will be available at `192.168.50.4` (unless you changed that in your `Vagrantfile`). To be able to use the web-based bits, we recommend to add a hostname to your `hosts` file:

    $ echo "192.168.50.4 mailinabox.lan" | sudo tee -a /etc/hosts

You should now be able to navigate to https://mailinabox.lan/admin using your browser. There should be an initial admin user with the name `me@mailinabox.lan` and the password `12345678`.

### Making changes

Your working copy of Mail-in-a-Box will be mounted inside your VM at `/vagrant`. Any change you make locally will appear inside your VM automatically.

Running `vagrant up --provision` again will repeat the installation with your modifications.

Alternatively, you can also ssh into the VM using:

    $ vagrant ssh

Once inside the VM, you can re-run individual parts of the setup like in this example:

    vm$ cd /vagrant
    vm$ sudo setup/owncloud.sh # replace with script you'd like to re-run

### Tests

Mail-in-a-Box needs more tests. If you're still looking for a way to help out, writing and contributing tests would be a great start!

## Public domain

This project is in the public domain. Copyright and related rights in the work worldwide are waived through the [CC0 1.0 Universal public domain dedication][CC0]. See the LICENSE file in this directory.

All contributions to this project must be released under the same CC0 wavier. By submitting a pull request or patch, you are agreeing to comply with this waiver of copyright interest.

[CC0]: http://creativecommons.org/publicdomain/zero/1.0/

## Code of Conduct

This project has a [Code of Conduct](CODE_OF_CONDUCT.md). Please review it when joining our community.
