# INSTALLATION GUIDE for Debian Mail-in-a-Box

=============

## Prerequisites

In order to install Debian Mail-in-a-Box, you need a machine with these mininum specifications:

- OS: Debian 12
- RAM: at least 512MB
- Disk: at least 6GB

Once you met these specifications, you need to install sudo. We could use ```su``` but is more easy to use the package ```sudo```.

```bash
 su -
 apt-get install sudo
 adduser [yourusername] sudo
 exit
 reboot
```

Now your user account have the sudo access.
After that, you need to install some utilities:

```bash
 sudo apt-get update
 sudo apt-get upgrade
 sudo apt-get install git
```

## Installing Debian Mail-in-a-Box

Now you can proceed with the installation of the mail server:

```bash
 git clone https://github.com/AiutoPcAmico/debian-mailinabox.git
 cd debian-mailinabox
 sudo ./setup/start.sh
```

During the setup, you have to answer different questions.

First, you need to specify the Locales framework.
Please, select **en_US.UTF-8 UTF-8** and default locale for the system environment **en_US.UTF8**

The script now installs all necessary packages. It might take some time (up to 15 minutes).
At the end, you'll need to answer a few questions about configuring Debian Mail-in-a-Box.

First of all you will be asked for an email address for configuring the mail server.
Usually it is configured as ```me@[servername].[domain].[tld]``` but personally I prefer to change it to ```[anotherusername]@[domain].[tld]```. 
This way Mail-in-a-Box will take care of the mail server for the main domain and the administrator user will be unknown.

Then you can indicate the subdomain where the mail server will be hosted (which you will reach via the Web GUI).
I recommend keeping the format ```box.[domain].[tld]```.

At last, select if you want to keep enabled postgrey greylist.

Once the setup script finished installing all the components (which can take a long time) you will be asked to create your first email account.
I recommend you setting it identical to the administration account ```[anotherusername]@[domain].[tld]```, so as to have a separate email for any logs or problems.

## Next Steps

Now your Debian Mail-in-a-Box is working!
You can reach your email admin page by following the url provided by the script.
You can now follow the guides from the official website to complete the setup and creation of your first email account.

Good luck!
AiutoPcAmico
