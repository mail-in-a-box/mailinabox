if [ -z "$EC2_KEYPAIR_NAME" ]; then
	EC2_KEYPAIR_NAME=mykey
fi

UBUNTU_CONFIG="us-east-1 13.04 amd64 instance-store"

export AMI=`curl -s http://cloud-images.ubuntu.com/locator/ec2/releasesTable | python3 tools/get_ubuntu_ami.py $UBUNTU_CONFIG`

ec2-create-group -d "mailinabox" "mailinabox"
for PORT in 25 587 993; do ec2-authorize mailinabox -P tcp -p $PORT -s 0.0.0.0/0; done

ec2run $AMI -k $EC2_KEYPAIR_NAME -t m1.small -z $AWS_AZ -g mailinabox > instance.info
export INSTANCE=`cat instance.info | grep INSTANCE | awk {'print $2'}`

echo Started instance $INSTANCE

sleep 5
while [ 1 ]
do
    export INSTANCE_IP=`ec2-describe-instances $INSTANCE | grep INSTANCE | awk {'print $14'}`
    if [ -z "$INSTANCE_IP" ]
    then
		echo "Waiting for $INSTANCE to start..."
    else
		break
    fi
    sleep 6
done

# Give SSH time to start.
sleep 5

echo New instance has IP: $INSTANCE_IP

