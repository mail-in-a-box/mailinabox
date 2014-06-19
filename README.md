Mail-in-a-Box
=============

Mail-in-a-Box helps individuals take back control of their email by defining a one-click, easy-to-deploy SMTP+everything else server: a mail server in a box.

**This is a work in progress. I work on this in my limited free time.**

Why build this? Mass electronic surveillance by governments revealed over the last year has spurred a new movement to [re-decentralize](http://redecentralize.org/) the web, that is, to empower netizens to be their own service providers again. SMTP, the protocol of email, is decentralized in principle but highly centralized in practice due to the high cost of implementing all of the modern protocols that surround it. As a result, most individuals trade their independence for access to a “free” email service.


The Box
-------

Mail-in-a-Box turns a fresh Ubuntu 14.04 LTS 64-bit machine into a working mail server, including:

* An [SMTP server](http://www.postfix.org/) for sending/receiving mail, with STARTTLS required to protect your password and [opportunistic TLS](https://en.wikipedia.org/wiki/Opportunistic_encryption) to prevent mass surveillance.
* An [IMAP server](http://dovecot.org/) for checking your mail, with SSL/TLS required to protect your password.
* [Webmail](http://roundcube.net/) over HTTPS so you can check your email from any web browser.
* [Spam filtering](https://spamassassin.apache.org/) that puts spam into a spam folder and [greylisting](http://postgrey.schweikert.ch/) to stop spam as it arrives.
* [SPF](https://en.wikipedia.org/wiki/Sender_Policy_Framework), [DKIM](https://en.wikipedia.org/wiki/DomainKeys_Identified_Mail), and [DMARC](https://en.wikipedia.org/wiki/DMARC) to prove to recipients that your email was from you --- the machine acts as its own DNS nameserver to automatically set this up.
* [DNSSEC](https://en.wikipedia.org/wiki/DNSSEC) and [DANE TLSA](https://en.wikipedia.org/wiki/DNS-based_Authentication_of_Named_Entities) to force cryptographically-secure communications in certain cases, especially between Mail-in-a-Boxes, if you add "DS" records to your domain registration.
* Configuration of mailboxes and mail aliases is done using a command-line tool or an HTTP-based API (accessible from within the server only).
* Basic system services like a firewall, intrusion protection, and setting the system clock are automatically configured.

This setup is what has been powering my own personal email since September 2013.

Please see the initial and very barebones [Documentation](docs/index.md) for more information on how to set up a Mail-in-a-Box. But in short, it's like this:

	# do this on a fresh install of Ubuntu 14.04 only!
	sudo apt-get install -y git
	git clone https://github.com/joshdata/mailinabox
	cd mailinabox
	sudo setup/start.sh

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
* Mail-in-a-Box was a semifinalist in the 2014 [Knight News Challenge](https://www.newschallenge.org/challenge/2014/submissions/mail-in-a-box), but it was not selected as a winner.
