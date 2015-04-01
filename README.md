Mail-in-a-Box
=============

By [@JoshData](https://github.com/JoshData) and [contributors](https://github.com/mail-in-a-box/mailinabox/graphs/contributors).

Mail-in-a-Box helps individuals take back control of their email by defining a one-click, easy-to-deploy SMTP+everything else server: a mail server in a box.

**Please see [https://mailinabox.email](https://mailinabox.email) for the project's website and setup guide!**

* * *

I am trying to:

* Make deploying a good mail server easy.
* Promote [decentralization](http://redecentralize.org/), innovation, and privacy on the web.
* Have automated, auditable, and [idempotent](http://sharknet.us/2014/02/01/automated-configuration-management-challenges-with-idempotency/) configuration.
* **Not** be a mail server that the NSA cannot hack.
* **Not** be customizable by power users.

The long-term goal is to have this be a one-click email appliance with *no* user-configurable setup options.

For more background, see [The Rationale](https://github.com/mail-in-a-box/mailinabox/wiki).

This setup is what has been powering my own personal email since September 2013.

The Box
-------

Mail-in-a-Box turns a fresh Ubuntu 14.04 LTS 64-bit machine into a working mail server, including SMTP ([postfix](http://www.postfix.org/)), IMAP ([dovecot](http://dovecot.org/)), Exchange ActiveSync ([z-push](https://github.com/fmbiete/Z-Push-contrib)), webmail ([Roundcube](http://roundcube.net/)), spam filtering ([spamassassin](https://spamassassin.apache.org/)), greylisting ([postgrey](http://postgrey.schweikert.ch/)), CardDAV/CalDAV ([ownCloud](http://owncloud.org/)), DNS, [SPF](https://en.wikipedia.org/wiki/Sender_Policy_Framework), DKIM ([OpenDKIM](http://www.opendkim.org/)), [DMARC](https://en.wikipedia.org/wiki/DMARC), [DNSSEC](https://en.wikipedia.org/wiki/DNSSEC), [DANE TLSA](https://en.wikipedia.org/wiki/DNS-based_Authentication_of_Named_Entities), [SSHFP](https://tools.ietf.org/html/rfc4255), and basic system services like a firewall, intrusion protection, and setting the system clock.

Authenticity
------------

I sign the release tags. To verify that a tag is signed by me, you can perform the following steps:

	# Download my PGP key.
	$ curl -s https://keybase.io/joshdata/key.asc | gpg --import
	gpg: key C10BDD81: public key "Joshua Tauberer <jt@occams.info>" imported

	# Clone this repository.
	$ git clone https://github.com/mail-in-a-box/mailinabox
	$ cd mailinabox

	# Verify the tag.
	$ git verify-tag v0.08
	gpg: Signature made ..... using RSA key ID C10BDD81
	gpg: Good signature from "Joshua Tauberer <jt@occams.info>"
	gpg: WARNING: This key is not certified with a trusted signature!
	gpg:          There is no indication that the signature belongs to the owner.
	Primary key fingerprint: 5F4C 0E73 13CC D744 693B  2AEA B920 41F4 C10B DD81

The key ID and fingerprint above should match my [Keybase.io key](https://keybase.io/joshdata) and the fingerprint I publish on [my homepage](https://razor.occams.info/).

The Acknowledgements
--------------------

This project was inspired in part by the ["NSA-proof your email in 2 hours"](http://sealedabstract.com/code/nsa-proof-your-e-mail-in-2-hours/) blog post by Drew Crawford, [Sovereign](https://github.com/al3x/sovereign) by Alex Payne, and conversations with <a href="http://twitter.com/shevski" target="_blank">@shevski</a>, <a href="https://github.com/konklone" target="_blank">@konklone</a>, and <a href="https://github.com/gregelin" target="_blank">@GregElin</a>.

Mail-in-a-Box is similar to [iRedMail](http://www.iredmail.org/) and [Modoboa](https://github.com/tonioo/modoboa).

The History
-----------

* In 2007 I wrote a relatively popular Mozilla Thunderbird extension that added client-side SPF and DKIM checks to mail to warn users about possible phishing: [add-on page](https://addons.mozilla.org/en-us/thunderbird/addon/sender-verification-anti-phish/), [source](https://github.com/JoshData/thunderbird-spf).
* Mail-in-a-Box was a semifinalist in the 2014 [Knight News Challenge](https://www.newschallenge.org/challenge/2014/submissions/mail-in-a-box), but it was not selected as a winner.
* Mail-in-a-Box hit the front page of Hacker News in [April](https://news.ycombinator.com/item?id=7634514) and [September](https://news.ycombinator.com/item?id=8276171) 2014.
