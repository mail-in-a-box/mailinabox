# Mail-in-a-Box Dockerfile
# see https://www.docker.io
###########################

# Change to this directory and then
# sudo docker.io build -t box .
# sudo docker.io run -i -t box

# Revert to phusion's baseimage once they upgrade to Ubuntu 14.04
#FROM phusion/baseimage:<version-based-on-14.04>
# For now use an upgraded image provided by pjz, based on his
# a PR: https://github.com/phusion/baseimage-docker/pull/64
FROM pjzz/phusion-baseimage:0.9.10
MAINTAINER Joshua Tauberer (http://razor.occams.info)

ENV PUBLIC_HOSTNAME box.local

# The PUBLIC_IP is only used for serving DNS, which means it is only
# useful if we set it to the host machine's IP address and have the
# host forward its port 53 (TCP/UDP) traffic to the docker container.
# Since we can't get the host's IP address here, we'll set this to
# a dummy value.
ENV PUBLIC_IP 127.0.122.123

# Turn off password-based authentication; for ssh access see the phusion-baseimage docs
RUN sed -i 's/^#\s*\(PasswordAuthentication no\)/\1/' /etc/ssh/sshd_config

# install some tools to install mailinabox
RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -q -y git ca-certificates wget && apt-get clean

# actually install mailinabox
RUN git clone https://github.com/joshdata/mailinabox
RUN cd mailinabox && scripts/start.sh

# configure mailinabox services
ADD setup_services.sh /usr/local/bin/setup_services.sh
RUN bash /usr/local/bin/setup_services.sh

EXPOSE 22 25 53 443 587 993
