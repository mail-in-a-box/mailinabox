export AMI=`curl http://cloud-images.ubuntu.com/locator/ec2/releasesTable | python3 tools/get_ubunut_ami.py us-east-1 13.04 amd64 instance-store`
ec2run $AMI -k mykey -t m1.small -z $AWS_AZ | tee instance.info
export INSTANCE=`cat instance.info | grep INSTANCE | awk {'print $2'}`
sleep 5
while [ 1 ]
do
	export INSTANCE_IP=`ec2-describe-instances $INSTANCE | grep INSTANCE | awk {'print $14'}`
    if [ -z "$INSTANCE_IP" ]
    then
		echo "Waiting for $INSTANCE to start..."
    else
		exit
    fi
    sleep 6
done

echo New instance started: $INSTANCE_IP

