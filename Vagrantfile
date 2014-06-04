# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu14.04-gitmachine"
  config.vm.box_url = "ubuntu14.04-gitmachine.box"

  # Network config: Since it's a mail server, it only makes sense
  # to put it on the public network. This will let the machine
  # take an IP address from your DHCP server. It's up to you to
  # make sure its ports are exposed on the public web.
  config.vm.hostname = "mailinabox"
  config.vm.network "public_network"

  config.vm.provision :shell, :inline => <<-SH
	# Our install will fail if SSH is installed and allows password-based authentication.
	# `vagrant ssh` will still work if we disable password authentication.
	echo "PasswordAuthentication no" >> /etc/ssh/sshd_config

	# Set environment variables so that the setup script does
	# not ask any questions during provisioning. We'll let the
	# machine figure out its own public IP and it'll take a
	# subdomain on our justtesting.email domain so we can get
	# started quickly.
    export PUBLIC_IP=auto-web
    export PUBLIC_HOSTNAME=auto-easy
    export CSR_COUNTRY=US

    # Start the setup script.
    cd /vagrant
    setup/start.sh
SH
end
