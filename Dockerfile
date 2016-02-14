# Mail-in-a-Box Dockerfile
###########################
#
# This file lets Mail-in-a-Box run inside of Docker (https://docker.io),
# a virtualization/containerization manager.
#
# Run:
#   $ containers/docker/run.sh
# to build the image, launch a storage container, and launch a Mail-in-a-Box
# container.
#
###########################################

# We need a better starting image than docker's ubuntu image because that
# base image doesn't provide enough to run most Ubuntu services. See
# http://phusion.github.io/baseimage-docker/ for an explanation.

FROM phusion/baseimage:0.9.16

# Dockerfile metadata.
MAINTAINER Joshua Tauberer (http://razor.occams.info)
EXPOSE 25 53/udp 53/tcp 80 443 587 993 4190
VOLUME /home/user-data

# Use baseimage's init system. A correct init process is required for
# process #1 in order to have a functioning Linux system.
CMD ["/sbin/my_init"]

# Create the user-data user, so the start script doesn't have to.
RUN useradd -m user-data

# Add project specific repo for dovecot and postgrey
RUN add-apt-repository -y ppa:mail-in-a-box/ppa

# Docker has a beautiful way to cache images after each step. The next few
# steps of installing system packages are very intensive, so we take care
# of them early and let docker cache the image after that, before doing
# any Mail-in-a-Box specific system configuration. That makes rebuilds
# of the image extremely fast.

# Update system packages.
RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# Install packages needed by Mail-in-a-Box.
ADD containers/docker/apt_package_list.txt /tmp/mailinabox_apt_package_list.txt
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y $(cat /tmp/mailinabox_apt_package_list.txt)

# from questions.sh -- needs merging into the above line
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y dialog python3 python3-pip
RUN pip3 install "email_validator==0.1.0-rc4"

# Now add Mail-in-a-Box to the system.
ADD . /usr/local/mailinabox

# Configure runit services.
RUN /usr/local/mailinabox/containers/docker/tools/configure_services.sh

# Add my_init scripts
ADD containers/docker/my_init.d/* /etc/my_init.d/
