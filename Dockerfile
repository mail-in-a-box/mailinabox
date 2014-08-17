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

FROM phusion/baseimage:0.9.15

# Dockerfile metadata.
MAINTAINER Joshua Tauberer (http://razor.occams.info)
EXPOSE 22 25 53 80 443 587 993

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
RUN rm -f /tmp/mailinabox_apt_package_list.txt

# Now add Mail-in-a-Box to the system.
ADD . /usr/local/mailinabox

# We can't know things like the IP address where the container will eventually
# be deployed until the container is started. We also don't want to create any
# private keys during the creation of the image --- that should wait until the
# container is started too. So our whole setup process is deferred until the
# container is started.
ENTRYPOINT ["/usr/local/mailinabox/containers/docker/container_start.sh"]
