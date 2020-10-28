Vagrant commands that you'd need most:
1. _To view the list of vagrant boxes, use `vagrant box list`_
2. _To initialize a vagrant VM, use `vagrant init boxname`_
3. _To start a vagrant VM, use `vagrant up`_
4. _To shut down the vagrant VM, use `vagrant halt ubuntu/bionic64`_
5. _To remove a vagrant box, use `vagrant box remove <boxname>`_


UserName and Password

1. _Generally vagrant created VM's username is `vagrant`, password is `vagrant`_
2. _hostname/ IP address will be available in
`config.vm.network "private_network", ip:  <if there is any>`. _


Errors encountered while setting up MIAB
1. _If you're seeing an error message about your *IP address being listed in the Spamhaus Block List*,
simply uncomment the `export SKIP_NETWORK_CHECKS=1` line in `Vagrantfile`.
It's normal, you're probably using a dynamic IP address assigned by your Internet provider–they're almost all listed._
2. _If you're seeing an error message such as this `Bash script and /bin/bash^M: bad interpreter: No such file or directory`,
 then most likely you're on windows host and your vm is ubuntu.
 Then you've to change the format of all .py and .sh files in all the mailinabox directories to Unix (LF)._
3. _If you're encountering migration error, please add this line *return* in line 216 at setup/migrate.py.
Then after the up --provision command is successful, you gotta uncomment this or remove this line. (Not sure yet)_
4. _If your vagrant up command is stuck at upgrading to nextcloud, it is because the nextcloud server is either down
or very slow. Check the /tmp folder whether the nextcloud.zip is being downloaded.
If not, download it yourself and paste it in the /tmp folder._
5. _As your vagrant VM is CLI, to see the contents of 192.168.50.4, do the following._


To make sure that you can view the curl contents in your host machine's browser by executing commands from guest VM CLI, these
are the steps that you gotta follow:
1. _Copy the private key that vagrant generated for you and paste it in .ssh directory (for windows: by default this is the path `C:\\Users\HP\.ssh folder`) with a name_
2. _Now if you try to login using the following SSH command,
   `ssh -i <path to your private key> username@hostname or username@ipaddress`
3. _You should be logged in to the vagrant VM_
4. _CD into the directory /etc/ssh_
5. _Edit the sshd_config file with sudo permission and uncomment these 3 lines:_

	`X11Forwarding yes`

	`X11DisplayOffset 10`

	`X11UseLocalhost yes`
6. _Now restart the sshd service by the following command:_
    `sudo systemctl restart sshd`
7. _logout from your account_
8. _If you're in ubuntu host, then do the following:_
		`ssh -X -i <path to your private key> username@hostname or username@ipaddress`
	   _you should be logged into the host as username. type `echo $DISPLAY` and see whether `localhost=10.0.0` comes up or not.
	   If it does, then X11Forwarding is enabled. Now type firefox in your terminal
	   and you should see the output in firefox browser in your ubuntu host machine
9. _If you're in windows host, install XMing and Putty_

	a) _Open Puttygen app and from conversions -> import key, load the key you saved in line 6_

	b) _Save the key by pressing save private key button in the same folder_

	c) _In Putty, go to Connections->SSH->Auth and load the private key by clicking load key button_

	d) _go to Connections->SSH->X11 and tick on X11forwarding_

	e) _Now, write the IP address/ hostname in sessions, save it with a session name and click on open._

	f) _Type vagrant as username and you should be logged in with X11 forwarding option enabled_

	g) _To check this option, type $ echo $DISPLAY and see whether localhost=10.0.0 comes up or not. If it does, then you're good to go._

	h) _Now type firefox in your putty terminal and you should see the output in firefox browser in your windows host machine_
