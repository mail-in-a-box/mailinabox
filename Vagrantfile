# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu14.04"
  config.vm.box_url = "http://cloud-images.ubuntu.com/vagrant/trusty/current/trusty-server-cloudimg-amd64-vagrant-disk1.box"

  # Network config: Since it's a mail server, the machine must be connected
  # to the public web. However, we currently don't want to expose SSH since
  # the machine's box will let anyone log into it. So instead we'll put the
  # machine on a private network.
  config.vm.hostname = "mailinabox"
  config.vm.network "private_network", ip: "192.168.50.4"

  # Forward required ports from host machine, in order to dispose
  # the mailserver to the public network.

  # DNS Server
  config.vm.network "forwarded_port", guest: 53, host: 53, protocol: "udp"
  config.vm.network "forwarded_port", guest: 53, host: 53, protocol: "tcp"

  # SMTP
  config.vm.network "forwarded_port", guest: 25, host: 25

  # IMAP SSL
  config.vm.network "forwarded_port", guest: 587, host: 587, protocol: "tcp"

  # IMAP4 SSL
  config.vm.network "forwarded_port", guest: 993, host: 993, protocol: "tcp"

  # POP3 SSL
  config.vm.network "forwarded_port", guest: 995, host: 995, protocol: "tcp"

  # Sieve
  config.vm.network "forwarded_port", guest: 4190, host: 4190

  # HTTPS/HTTP
  # Hint: You can expose this to a different port if your host machine already
  # has a webserver configured on default ports (e.g.: 11080 | 11443)
  # @todo: Fix menu items if a custom port is selected to add the new ports
  # to the routes.
  config.vm.network "forwarded_port", guest: 80, host: 80, protocol: "tcp"
  config.vm.network "forwarded_port", guest: 443, host: 443, protocol: "tcp"

  # Pyzor
  config.vm.network "forwarded_port", guest: 24441, host: 24441, protocol: "udp"

  # Postfix
  config.vm.network "forwarded_port", guest: 20025, host: 20025, protocol: "udp"
  config.vm.network "forwarded_port", guest: 20025, host: 20025, protocol: "tcp"

  # Enable NatAliasMode to forward real ip addresses in log files
  config.vm.provider "virtualbox" do |v|
    v.customize ["modifyvm", :id, "--nataliasmode1", "proxyonly"]
  end

  config.vm.provision :shell, :inline => <<-SH
	# Set environment variables so that the setup script does
	# not ask any questions during provisioning. We'll let the
	# machine figure out its own public IP and it'll take a
	# subdomain on our justtesting.email domain so we can get
	# started quickly.
    export NONINTERACTIVE=1
    export PUBLIC_IP=auto
    export PUBLIC_IPV6=auto
    export PRIMARY_HOSTNAME=auto-easy
    #export SKIP_NETWORK_CHECKS=1

    # Start the setup script.
    cd /vagrant
    setup/start.sh
SH
end
