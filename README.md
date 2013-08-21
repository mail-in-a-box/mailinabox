Mail in a Box
=============

One-click deployment of your own mail server and personal cloud (so to speak).

This draws heavily on Sovereign by Alex Payne (https://github.com/al3x/sovereign) and the "NSA-proof your email in 2 hours" blog post by Drew Crawford (http://sealedabstract.com/code/nsa-proof-your-e-mail-in-2-hours/).

Deploying to EC2 from the command line
--------------------------------------

Sign up for Amazon Web Services.

Create an Access Key at https://console.aws.amazon.com/iam/home?#security_credential. Download the key and save the information somewhere secure.

Set up your environment and paste in the two parts of your access key that you just downloaded: 

	sudo apt-get install ec2-api-tools

	export AWS_ACCESS_KEY=your_access_key_id
	export AWS_SECRET_KEY=your_secret_key
	export EC2_URL=ec2.us-east-1.amazonaws.com
	export AWS_AZ=us-east-1a
	
The first time around, create a new volume (disk drive) to store your stuff.

	source ec2/new_volume.sh
	
If you want to reuse an existing volume:

	export VOLUME_ID=...your existing volume id...
	
Here we're using the Ubuntu 13.04 amd64 instance-store-backed AMI in the us-east region. You can select another at http://cloud-images.ubuntu.com/locator/ec2/.

Generate a new "keypair" (if you don't have one) that will let you SSH into your machine after you start it:

	ec2addkey mykey > mykey.pem
	chmod go-rw mykey.pem

Then launch a new instance. We're creating a m1.small instance --- it's the smallest instance that can use an instance-store-backed AMI. So charges will start to apply.

	source ec2/start_instance.sh

It will wait until the instance is available.

You'll probably want to associate it with an Elastic IP. If you do, you'll need to update the INSTANCE_IP variable.
	
Configure the server:

	ssh -i mykey.pem ubuntu@$INSTANCE_IP

Somehow download these files.

	sh scripts/index.sh
	...
	logout

Terminate your instance with:

	ec2-terminate-instances $INSTANCE


