#!/bin/bash
# Use this script to launch Mail-in-a-Box within a docker container.
# ==================================================================
#
# A base image is created first. The base image installs Ubuntu
# packages and pulls in the Mail-in-a-Box source code. This is
# defined in Dockerfile at the root of this repository.
#
# A mailinabox-userdata container is started next. This container
# contains nothing but a shared volume for storing user data.
# It is segregated from the rest of the live system to make backups
# easier.
#
# The mailinabox-services container is started last. It is the
# real thing: it runs the mailinabox image. This container will
# initialize itself and will initialize the mailinabox-userdata
# volume if the volume is new.


DOCKER=docker

# Build or rebuild the image.
# Rebuilds are very fast.
$DOCKER build -q -t mailinabox .

if ! $DOCKER ps -a | grep mailinabox-userdata > /dev/null; then
	echo Starting user-data volume container...
	$DOCKER run -d \
		--name mailinabox-userdata \
		-v /home/user-data \
		scratch /bin/bash
fi

# End a running container.
if $DOCKER ps -a | grep mailinabox-services > /dev/null; then
	echo Deleting container...
	$DOCKER rm mailinabox-services
fi

# Start container.
echo Starting new container...
$DOCKER run \
	--privileged \
	-v /dev/urandom:/dev/random \
	-p 25 -p 53/udp -p 53/tcp -p 80 -p 443 -p 587 -p 993 \
	--name mailinabox-services \
	--volumes-from mailinabox-userdata \
	mailinabox