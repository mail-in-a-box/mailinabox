# Mail-in-a-Box Dockerfile
# see https://www.docker.io
###########################

# To build the image:
# sudo docker.io build -t box .

# To run a container for testing (with a command prompt and no publicly exposed ports):
# sudo docker.io run -i -t -P box

# Or to run in the background and expose all of the ports so that the *host* acts as a Mail-in-a-Box:
# (the SSH port is only available locally, but other ports are exposed publicly and must be available
# otherwise the container won't start)
# sudo docker.io run -d -p 22 -p 25:25 -p 53:53/udp -p 443:443 -p 587:587 -p 993:993 box

FROM ubuntu:14.04
MAINTAINER Joshua Tauberer (http://razor.occams.info)

# We can't know these values ahead of time, so set them to something
# obviously local. The start.sh script will need to be run again once
# these values are known. 
ENV PUBLIC_HOSTNAME box.local
ENV PUBLIC_IP 127.0.123.123

# Docker-specific Mail-in-a-Box configuration.
ENV DISABLE_FIREWALL 1

# Our install will fail if SSH is installed and allows password-based authentication.
RUN DEBIAN_FRONTEND=noninteractive apt-get install -qq -y openssh-server
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
