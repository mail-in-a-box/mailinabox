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

# Use baseimage init system
CMD ["/sbin/my_init"]

# Create the user-data user, so the start script doesn't have to.
RUN useradd -m user-data

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

# Now add Mail-in-a-Box to the system.
ADD . /usr/local/mailinabox

# Patch setup/functions.sh
RUN cp /usr/local/mailinabox/setup/functions.sh /usr/local/mailinabox/setup/functions.orig.sh
RUN echo "# Docker patches" >> /usr/local/mailinabox/setup/functions.sh && \
	echo "source containers/docker/patch/setup/functions_docker.sh" >> /usr/local/mailinabox/setup/functions.sh
# Skip apt-get install
RUN sed 's/PACKAGES=$@/PACKAGES=""/g' -i /usr/local/mailinabox/setup/functions.sh

# Install runit services
ADD containers/docker/runit/ /etc/service/

# LSB Compatibility
RUN /usr/local/mailinabox/containers/docker/tools/lsb_compat.sh

# Configure service logs
RUN /usr/local/mailinabox/containers/docker/tools/runit_logs.sh

# Disable services
RUN /usr/local/mailinabox/containers/docker/tools/disable_services.sh

# Add my_init scripts
ADD containers/docker/my_init.d/* /etc/my_init.d/
