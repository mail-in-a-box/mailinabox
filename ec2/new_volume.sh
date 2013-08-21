export VOLUME_SIZE=1 # in GiB (2^30 bytes)
ec2-create-volume -s $VOLUME_SIZE -z $AWS_AZ > volume.info
export VOLUME_ID=`cat volume.info |  awk {'print $2'}`
export VOLUME_IS_NEW=1
echo Created new volume: $VOLUME_ID

