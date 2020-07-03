# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  # Recreate our conditions
  config.vm.box = "generic/debian10"
  config.vm.provider "hyperv" do |v|
    v.memory = 1024
    v.cpus = 1
  end

  # Network config: Since it's a mail server, the machine must be connected
  # to the public web. However, we currently don't want to expose SSH since
  # the machine's box will let anyone log into it. So instead we'll put the
  # machine on a private network.
  config.vm.hostname = "mailinabox.lan"
  config.vm.network "private_network", ip: "192.168.50.4"

  config.vm.provision :shell, :inline => <<-SH
    # Set environment variables so that the setup script does
    # not ask any questions during provisioning. We'll let the
    # machine figure out its own public IP.
    export NONINTERACTIVE=1
    export PUBLIC_IP=auto
    export PUBLIC_IPV6=auto
    export PRIMARY_HOSTNAME=auto
    #export SKIP_NETWORK_CHECKS=1

    if [ ! git ]
    then
      apt update
      apt install git
    fi

    if [ ! -d /mailinabox ];
    then
      git clone https://github.com/ddavness/power-mailinabox.git /mailinabox
    fi

    # Start the setup script.
    cd /mailinabox
    git checkout development
    git pull

    setup/start.sh
SH
end
