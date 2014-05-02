# Mail-in-a-Box Dockerfile
# see https://www.docker.io
###########################

# sudo docker.io build -t box .
# sudo docker.io run -i -t box

FROM ubuntu:14.04
MAINTAINER Joshua Tauberer (http://razor.occams.info)

ENV PUBLIC_HOSTNAME box.local

# The PUBLIC_IP is only used for serving DNS, which means it is only
# useful if we set it to the host machine's IP address and have the
# host forward its port 53 (TCP/UDP) traffic to the docker container.
# Since we can't get the host's IP address here, we'll set this to
# a dummy value.
ENV PUBLIC_IP 127.0.123.123

# Our install will fail if SSH is installed and allows password-based authentication.
RUN apt-get install -q -y openssh-server
RUN sed -i /etc/ssh/sshd_config -e "s/^#PasswordAuthentication yes/PasswordAuthentication no/g"

# Add this repo into the image so we have the configuration scripts.
ADD scripts /usr/local/mailinabox/scripts
ADD conf /usr/local/mailinabox/conf
ADD tools /usr/local/mailinabox/tools

# Start the configuration.
RUN cd /usr/local/mailinabox; scripts/start.sh

# How the instance is launched.
ADD containers/docker /usr/local/mailinabox/containers/docker
CMD bash /usr/local/mailinabox/containers/docker/start_services.sh
EXPOSE 22 25 53 443 587 993
