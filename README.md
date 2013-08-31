Mail in a Box
=============

One-click deployment of your own mail server and personal cloud (so to speak).

This draws heavily on the "NSA-proof your email in 2 hours" blog post by Drew Crawford (http://sealedabstract.com/code/nsa-proof-your-e-mail-in-2-hours/) and Sovereign by Alex Payne (https://github.com/al3x/sovereign). I've made some tweaks to their setups.

Before You Begin
----------------

* Decide what **hostname** you'll use for your new Mail in a Box. You may want to buy a domain name from your favorite registrar now. For the most flexibility, assign a subdomain to your box. For instance, my domain name is `occams.info` (my email address is something`@occams.info`), so I've assigned `box.occams.info` as the hostname for my Mail in a Box.

Get a Server
------------

* Get a server. I've been a long-time customer of Rimuhosting.com which provides cheap VPS machines at several locations around the world. You could also go with Linode.com or any other cloud or VPS (virtual server) provider. (If you want to test on Amazon EC2, I've got instructions for you in ec2/README.md.) In a cloud environment like EC2 where your server's IP address is dynamic, this is a good time to assign a static IP (like a EC2 Elastic IP).

* Choose Ubuntu 13.04 amd64 as your operating system (aka a Linux distribution). You won't need much memory or disk space. 768 MB of memory (RAM) and 4G of disk space should be plenty.

* Once the machine is running, set up Reverse DNS. Each ISP handles that differently. You'll have to figure out from your ISP how to do that. Set the reverse DNS to the hostname you chose above (in my case `box.occams.info`).

* Log in with SSH. Again, your ISP will probably give you some instructions on how to do that. If your personal computer has a command line, you'll be doing something like this:

	ssh -i yourkey.pem user@10.20.30.40
	
You should see a command prompt roughly similar to:

	root@box:~# (<-- blinking cursor here)

	
All command-line instructions below assume you've logged into your machine with SSH already.

Configuring the Server
----------------------

After logging into your server with SSH, type the following in the console:

	sudo apt-get install -y git
	git clone https://github.com/tauberer/mailinabox
	cd mailinabox
	
Now you've got the Mail in a Box source code stored on your server. The next command starts the automatic configuration of the server:
	
	sudo scripts/start.sh
	
You will be asked to enter the hostname you chose and the public IP address of the server as assigned by your ISP.

After that you'll see a lot of output as system programs are installed and configured.

At the end you'll be asked to create a mail user for the system. Enter the user's email address (which is also his IMAP/SMTP username) and then its password.

It is safe to run the start script again in case something went wrong.

