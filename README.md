Mail-in-a-Box
=============

By [@JoshData](https://github.com/JoshData) and [contributors](https://github.com/mail-in-a-box/mailinabox/graphs/contributors).

Mail-in-a-Box helps individuals take back control of their email by defining a one-click, easy-to-deploy SMTP+everything else server: a mail server in a box.

**Please see [https://mailinabox.email](https://mailinabox.email) for the project's website and setup guide!**

* * *

Our goals are to:

* Make deploying a good mail server easy.
* Promote [decentralization](http://redecentralize.org/), innovation, and privacy on the web.
* Have automated, auditable, and [idempotent](https://sharknet.us/2014/02/01/automated-configuration-management-challenges-with-idempotency/) configuration.
* **Not** make a totally unhackable, NSA-proof server.
* **Not** make something customizable by power users.

Additionally, this project has a [Code of Conduct](CODE_OF_CONDUCT.md), which supersedes the goals above. Please review it when joining our community.

The Box
-------

Mail-in-a-Box turns a fresh Ubuntu 14.04 LTS 64-bit machine into a working mail server by installing and configuring various components.

It is a one-click email appliance. There are no user-configurable setup options. It "just works".

The components installed are:

* SMTP ([postfix](http://www.postfix.org/)), IMAP ([dovecot](http://dovecot.org/)), CardDAV/CalDAV ([ownCloud](https://owncloud.org/)), Exchange ActiveSync ([z-push](https://github.com/fmbiete/Z-Push-contrib))
* Webmail ([Roundcube](http://roundcube.net/)), static website hosting ([nginx](http://nginx.org/))
* Spam filtering ([spamassassin](https://spamassassin.apache.org/)), greylisting ([postgrey](http://postgrey.schweikert.ch/))
* DNS ([nsd4](https://www.nlnetlabs.nl/projects/nsd/)) with [SPF](https://en.wikipedia.org/wiki/Sender_Policy_Framework), DKIM ([OpenDKIM](http://www.opendkim.org/)), [DMARC](https://en.wikipedia.org/wiki/DMARC), [DNSSEC](https://en.wikipedia.org/wiki/DNSSEC), [DANE TLSA](https://en.wikipedia.org/wiki/DNS-based_Authentication_of_Named_Entities), and [SSHFP](https://tools.ietf.org/html/rfc4255) records automatically set
* Backups ([duplicity](http://duplicity.nongnu.org/)), firewall ([ufw](https://launchpad.net/ufw)), intrusion protection ([fail2ban](http://www.fail2ban.org/wiki/index.php/Main_Page)), system monitoring ([munin](http://munin-monitoring.org/))

It also includes:

* A control panel and API for adding/removing mail users, aliases, custom DNS records, etc. and detailed system monitoring.
* Our own builds of postgrey (adding better whitelisting) and dovecot-lucene (faster search for mail) distributed via the [Mail-in-a-Box PPA](https://launchpad.net/~mail-in-a-box/+archive/ubuntu/ppa) on Launchpad.

For more information on how Mail-in-a-Box handles your privacy, see the [security details page](security.md).

Installation
------------

See the [setup guide](https://mailinabox.email/guide.html) for detailed, user-friendly instructions.

For experts, start with a completely fresh (really, I mean it) Ubuntu 14.04 LTS 64-bit machine. On the machine...

Clone this repository:

	$ git clone https://github.com/mail-in-a-box/mailinabox
	$ cd mailinabox

_Optional:_ Download my PGP key and then verify that the sources were signed
by me:

	$ curl -s https://keybase.io/joshdata/key.asc | gpg --import
	gpg: key C10BDD81: public key "Joshua Tauberer <jt@occams.info>" imported

	$ git verify-tag v0.19a
	gpg: Signature made ..... using RSA key ID C10BDD81
	gpg: Good signature from "Joshua Tauberer <jt@occams.info>"
	gpg: WARNING: This key is not certified with a trusted signature!
	gpg:          There is no indication that the signature belongs to the owner.
	Primary key fingerprint: 5F4C 0E73 13CC D744 693B  2AEA B920 41F4 C10B DD81

You'll get a lot of warnings, but that's OK. Check that the primary key fingerprint matches the
fingerprint in the key details at [https://keybase.io/joshdata](https://keybase.io/joshdata)
and on my [personal homepage](https://razor.occams.info/). (Of course, if this repository has been compromised you can't trust these instructions.)

Checkout the tag corresponding to the most recent release:

	$ git checkout v0.19a

Begin the installation.

	$ sudo setup/start.sh

For help, DO NOT contact me directly --- I don't do tech support by email or tweet (no exceptions).

Post your question on the [discussion forum](https://discourse.mailinabox.email/) instead, where me and other Mail-in-a-Box users may be able to help you.

The Acknowledgements
--------------------

This project was inspired in part by the ["NSA-proof your email in 2 hours"](http://sealedabstract.com/code/nsa-proof-your-e-mail-in-2-hours/) blog post by Drew Crawford, [Sovereign](https://github.com/sovereign/sovereign) by Alex Payne, and conversations with <a href="https://twitter.com/shevski" target="_blank">@shevski</a>, <a href="https://github.com/konklone" target="_blank">@konklone</a>, and <a href="https://github.com/gregelin" target="_blank">@GregElin</a>.

Mail-in-a-Box is similar to [iRedMail](http://www.iredmail.org/) and [Modoboa](https://github.com/tonioo/modoboa).

The History
-----------

* In 2007 I wrote a relatively popular Mozilla Thunderbird extension that added client-side SPF and DKIM checks to mail to warn users about possible phishing: [add-on page](https://addons.mozilla.org/en-us/thunderbird/addon/sender-verification-anti-phish/), [source](https://github.com/JoshData/thunderbird-spf).
* In August 2013 I began Mail-in-a-Box by combining my own mail server configuration with the setup in ["NSA-proof your email in 2 hours"](http://sealedabstract.com/code/nsa-proof-your-e-mail-in-2-hours/) and making the setup steps reproducible with bash scripts.
* Mail-in-a-Box was a semifinalist in the 2014 [Knight News Challenge](https://www.newschallenge.org/challenge/2014/submissions/mail-in-a-box), but it was not selected as a winner.
* Mail-in-a-Box hit the front page of Hacker News in [April](https://news.ycombinator.com/item?id=7634514) 2014, [September](https://news.ycombinator.com/item?id=8276171) 2014, and [May](https://news.ycombinator.com/item?id=9624267) 2015.
* FastCompany mentioned Mail-in-a-Box a [roundup of privacy projects](http://www.fastcompany.com/3047645/your-own-private-cloud) on June 26, 2015.
