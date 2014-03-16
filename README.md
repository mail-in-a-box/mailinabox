Mail-in-a-Box
=============

Mass electronic surveillance by governments revealed over the last year has spurred a new movement to re-decentralize the web, that is, to empower netizens to be their own service providers again. SMTP, the protocol of email, is decentralized in principle but highly centralized in practice due to the high cost of implementing all of the modern protocols that surround it. As a result, most individuals trade their independence for access to a “free” email service.

Mail-in-a-Box helps individuals take back control of their email by defining a one-click, easy-to-deploy SMTP+everything else server: a mail server in a box.

*This is a work in progress.*

On March 13, 2014 I submitted Mail-in-a-Box to the [Knight News Challenge](https://www.newschallenge.org/challenge/2014/submissions/mail-in-a-box).

The Box
-------

Mail-in-a-Box provides a single shell script that turns a fresh Ubuntu 13.04 64-bit machine into a working mail server, including:

* An SMTP server for sending/receiving mail, with STARTTLS required for authentication, and greylisting to cut down on spam (postfix, postgrey).
* An IMAP server for checking your mail, with SSL required (dovecot).
* A webmail client over SSL so you can check your email from a web browser (roundcube, nginx).
* Spam filtering with spam automatically going to your Spam folder (spamassassin).
* DKIM signing on outgoing messages (opendkim).
* The machine acts as its own DNS server and is automatically configured for SPF and DKIM (nsd3).
* Configuration of mailboxes and mail aliases is done using a command-line tool.
* Basic system services like a firewall, intrusion protection, and setting the system clock are automatically configured (ufw, fail2ban, ntp).

Since this is a work in progress certainly more, such as personal cloud services, could be added in the future.

This setup is what has been powering my own personal email since September 2013.

Please see the initial and very barebones [Documentation](docs/index.md) for more information on how to set up a Mail-in-a-Box. But in short, it's like this:

	sudo apt-get install -y git
	git clone https://github.com/tauberer/mailinabox
	cd mailinabox
	sudo scripts/start.sh

The Rationale
-------------

Mass electronic surveillance by governments that have been revealed over the last year has spurred a new movement to re-decentralize the web. Centralization of services has created efficiencies at the expense of freedom. One can get a “free” email account or a “free” social media account, but what the user gives up is his or her privacy, both explicitly as a term of service and implicitly as the service providers comply with classified government intelligence programs. Users put their sensitive communications at risk (think journalists, lawyers, investors, and innovators) also give up control of their Internet experience and the opportunity to innovate that experience.

Netizens are looking for ways to rely less on the large, centralized service providers such as Google and Yahoo and more on smaller providers or even themselves. Users of Mail-in-a-Box might be journalists, lawyers, and other individuals at risk for government surveillance, individuals communicating sensitive information who want to be protected from criminal activity, and anyone who prefers to take control over their experience on the Internet.

SMTP, the protocol of email, is an open protocol that is decentralized in principle but highly centralized in practice. While SMTP itself is a simple protocol, the demands of modern life have lead to the development of a constellation of other protocols in the last 15 years that are now required to have one’s outgoing mail delivered securely and reliably, and one’s incoming mail clean and secure. These protocols include SPF, DKIM, digital signatures, public key exchanges, TLS, DNSSEC, reputation management, spam and abuse reporting, spam filtering, and graylisting, to name a few.

Implementing all of the modern protocols that surround SMTP is difficult, and thus costly. As a result, most individuals trade their independence for access to a “free” email service, meaning one of the few, centralized services.

Mail-in-a-Box helps individuals take back control of their email by defining a one-click, easy-to-deploy SMTP+everything else server. It is a mail server in a box aimed to be deployed securely into any cloud infrastructure. It provides no user interface to send or check one’s mail but implements all of the underlying protocols that other applications (mail clients), such as Google K-9 for mobile devices, Mailpile, and Mozilla Thunderbird, can interoperate with.

The Goals / Next Steps
----------------------

Goals:

* Make the deployment of a mail server ridiculously easy.
* Configuration must be automated, concise, auditable, and idempotent.
* Promote decentralization, innovation, and privacy on the web.

Success is achieving any of that. I am *not* looking to create a mail server that the NSA cannot hack.

Next Steps:

* Finish the automated tests to verify that a system is functioning correctly.
* Backups. Restore backups to a new machine. Versioning and upgrading.
* Create a web-based UI for managing mail users.
* Document how to buy your own domain, set up DNS, rent a server, and improve the existing docs.
* Turn the scripts into Chef or Dockerize, simplify as much as possible.
* Make spam learning work. Maybe switch to dspam.
* Make IPV6 work. If the machine is at an IPV6 address, it may not work.

The Acknowledgements
--------------------

This project was inspired in part by the ["NSA-proof your email in 2 hours"](http://sealedabstract.com/code/nsa-proof-your-e-mail-in-2-hours/) blog post by Drew Crawford, [Sovereign](https://github.com/al3x/sovereign) by Alex Payne, and conversations with <a href="http://twitter.com/shevski" target="_blank">@shevski</a>, <a href="https://github.com/konklone" target="_blank">@konklone</a>, and <a href="https://github.com/gregelin" target="_blank">@GregElin</a>.

The History
-----------

* In 2007 I wrote a relatively popular Mozilla Thunderbird extension that added client-side SPF and DKIM checks to mail to warn users about possible phishing: [add-on page](https://addons.mozilla.org/en-us/thunderbird/addon/sender-verification-anti-phish/), [source](https://github.com/JoshData/thunderbird-spf).