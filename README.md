Mail-in-a-Box
=============

Mail-in-a-Box helps individuals take back control of their email by defining a one-click, easy-to-deploy SMTP+everything else server: a mail server in a box.

**This is a work in progress. I work on this in my limited free time.**

Why build this? Mass electronic surveillance by governments revealed over the last year has spurred a new movement to [re-decentralize](http://redecentralize.org/) the web, that is, to empower netizens to be their own service providers again. SMTP, the protocol of email, is decentralized in principle but highly centralized in practice due to the high cost of implementing all of the modern protocols that surround it. As a result, most individuals trade their independence for access to a “free” email service.


The Box
-------

Mail-in-a-Box turns a fresh Ubuntu 14.04 LTS 64-bit machine into a working mail server, including:

* An SMTP server for sending/receiving mail, with STARTTLS required for authentication, and greylisting to cut down on spam (postfix, postgrey).
* An IMAP server for checking your mail, with SSL required (dovecot).
* A webmail client over SSL so you can check your email from a web browser (roundcube, nginx).
* Spam filtering with spam automatically going to your Spam folder (spamassassin).
* DKIM signing on outgoing messages (opendkim).
* The machine acts as its own DNS server and is automatically configured for SPF and DKIM (nsd).
* Configuration of mailboxes and mail aliases is done using a command-line tool.
* Basic system services like a firewall, intrusion protection, and setting the system clock are automatically configured (ufw, fail2ban, ntp).

This setup is what has been powering my own personal email since September 2013.

Please see the initial and very barebones [Documentation](docs/index.md) for more information on how to set up a Mail-in-a-Box. But in short, it's like this:

	# do this on a fresh install of Ubuntu 14.04 only!
	sudo apt-get install -y git
	git clone https://github.com/joshdata/mailinabox
	cd mailinabox
	sudo scripts/start.sh

**Status**: This is a work in progress. It works for what it is, but it is missing such things as quotas, backup/restore, etc.

The Goals
---------

* Create a push-button "Email Appliance" for everyday users.
* Promote decentralization, innovation, and privacy on the web.
* Have automated, auditable, and [idempotent](http://sharknet.us/2014/02/01/automated-configuration-management-challenges-with-idempotency/) configuration.

For more background, see [The Rationale](https://github.com/JoshData/mailinabox/wiki).

What I am not trying to do:

* **Not** to be a mail server that the NSA cannot hack.
* **Not** to be customizable by power users.

The Acknowledgements
--------------------

This project was inspired in part by the ["NSA-proof your email in 2 hours"](http://sealedabstract.com/code/nsa-proof-your-e-mail-in-2-hours/) blog post by Drew Crawford, [Sovereign](https://github.com/al3x/sovereign) by Alex Payne, and conversations with <a href="http://twitter.com/shevski" target="_blank">@shevski</a>, <a href="https://github.com/konklone" target="_blank">@konklone</a>, and <a href="https://github.com/gregelin" target="_blank">@GregElin</a>.

Mail-in-a-Box is similar to [iRedMail](http://www.iredmail.org/).

The History
-----------

* In 2007 I wrote a relatively popular Mozilla Thunderbird extension that added client-side SPF and DKIM checks to mail to warn users about possible phishing: [add-on page](https://addons.mozilla.org/en-us/thunderbird/addon/sender-verification-anti-phish/), [source](https://github.com/JoshData/thunderbird-spf).
* On March 13, 2014 I submitted Mail-in-a-Box to the [Knight News Challenge](https://www.newschallenge.org/challenge/2014/submissions/mail-in-a-box).
