Mail-in-a-Box with Quotas
=========================

This is an experimental implementation of Mail-in-a-box with quota support.

Quotas can be set and viewed in the control panel

To set quotas from the command line, use:
 
    tools/mail.py user quota <email> <quota>

To set the system default quota for new users, use:
 
    tools/mail.py system default-quota <quota>

Mailbox size recalculation by Dovecot can be forced using the command:

    doveadm quota recalc -A

Please report any bugs on github.


Installing v0.41-quota
----------------------

To install the latest version, log into your box and execute the following commands:

	$ git clone https://github.com/jrsupplee/mailinabox.git
	$ cd mailinabox
    $ sudo bash setup/bootstrap.sh

Follow the standard directions for setting up an MiaB installation.  There are no special installation steps for installing this version.

The default quota is set to `0` which means unlimited.  If you want to set a different default quota, follow the directions above.


Upgrading v0.41 to v.0.41-quota
-------------------------------

This is experimental software.  You have been warned.

* Rename your `mailinabox` directory to something like `miab.old`

* Clone this repository using:

    `git clone https://github.com/jrsupplee/mailinabox.git`

* cd into `mailinabox` and run `sudo setup/bootstrap.sh`  On occasion there are lock errors when updating `Munin`.  Just re-run `sudo setup/start.sh` until the error does not occur.

* Note: all existing users at the time of the upgrade will have there quota set to `0` (unlimited).


Upgrading MiaB with quotas to a New Version
---------------------------------------

* `cd` into the `mailinabox` directory.

* Execute `git pull` to download the latest changes.

* Execute `sudo bash setup/bootstrap.sh` to checkout the latest version and re-run setup.


Issues
------

* When a user's quota is changed, any IMAP session running for that user will not recognize the new quota.  To solve this a `dovecot reload` could be issued causing all current IMAP sessions to be terminated.  On a system with many users, it might not be desirable to reset all users sessions to fix the quota for one user.  Also if the administrator is setting the quota for several users it would result in the continual reset of those connections. 


Changes
-------

### v0.41-quota-0.17-alpha

* Update the README

### v0.41-quota-0.16-alpha

* Update to v0.41 of Mail-in-a-Box

### v0.40-quota-0.16-alpha

* Fix problem with quota field on control panel that prevented adding users.

### v0.40-quota-0.15-alpha

* Fix bug where quotas are not recalculated when a user's quota is changed in control panel

### v0.40-quota-0.14-alpha

* When updating a user's quota, execute `doveadm quota recalc -u <email>` to forces an immediate recalculation of the user's quota.

* Add a thousands separator (,) to the messages count in the control panel user list.

* Execute `doveadm quota recalc -A` to force a recalculation of all user quotas when running `start.sh`.

* Get rid of the error message complaining that the `quota` column already exists when upgrading from a previous version of `v0.40-quota`.

### v0.40-quota-0.13-alpha

* Add a `default-quota` setting in `settings.yaml`.

* Add input for setting quota when entering a new user in control panel.

* Modify `tools/mail.py` to allow for setting and getting the default system quota.

* Modify `tools/mail.py` to allow for getting a user's quota setting.

* Modify the mail users list in control panel to display percentage of quota used.

### v0.40-quota-0.12-alpha

* Update README

### v0.40-quota-0.11-alpha

* Read latest version from this repository not the Mail-in-a-Box master repository

### v0.40-quota-0.1-alpha

* First experimental release of Mail-in-a-Box for quotas.
* Quotas are working and there is basic support in the control panel and `tools/mail.py`.


Reference Documents
-------------------

* https://blog.sys4.de/postfix-dovecot-mailbox-quota-en.html
* https://linuxize.com/post/install-and-configure-postfix-and-dovecot/


\[BEGIN Official README]

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

Mail-in-a-Box turns a fresh Ubuntu 18.04 LTS 64-bit machine into a working mail server by installing and configuring various components.

It is a one-click email appliance. There are no user-configurable setup options. It "just works".

The components installed are:

* SMTP ([postfix](http://www.postfix.org/)), IMAP ([dovecot](http://dovecot.org/)), CardDAV/CalDAV ([Nextcloud](https://nextcloud.com/)), Exchange ActiveSync ([z-push](http://z-push.org/))
* Webmail ([Roundcube](http://roundcube.net/)), static website hosting ([nginx](http://nginx.org/))
* Spam filtering ([spamassassin](https://spamassassin.apache.org/)), greylisting ([postgrey](http://postgrey.schweikert.ch/))
* DNS ([nsd4](https://www.nlnetlabs.nl/projects/nsd/)) with [SPF](https://en.wikipedia.org/wiki/Sender_Policy_Framework), DKIM ([OpenDKIM](http://www.opendkim.org/)), [DMARC](https://en.wikipedia.org/wiki/DMARC), [DNSSEC](https://en.wikipedia.org/wiki/DNSSEC), [DANE TLSA](https://en.wikipedia.org/wiki/DNS-based_Authentication_of_Named_Entities), and [SSHFP](https://tools.ietf.org/html/rfc4255) records automatically set
* Backups ([duplicity](http://duplicity.nongnu.org/)), firewall ([ufw](https://launchpad.net/ufw)), intrusion protection ([fail2ban](http://www.fail2ban.org/wiki/index.php/Main_Page)), system monitoring ([munin](http://munin-monitoring.org/))

It also includes:

* A control panel and API for adding/removing mail users, aliases, custom DNS records, etc. and detailed system monitoring.

For more information on how Mail-in-a-Box handles your privacy, see the [security details page](security.md).

Installation
------------

See the [setup guide](https://mailinabox.email/guide.html) for detailed, user-friendly instructions.

For experts, start with a completely fresh (really, I mean it) Ubuntu 18.04 LTS 64-bit machine. On the machine...

Clone this repository:

	$ git clone https://github.com/mail-in-a-box/mailinabox
	$ cd mailinabox

_Optional:_ Download Josh's PGP key and then verify that the sources were signed
by him:

	$ curl -s https://keybase.io/joshdata/key.asc | gpg --import
	gpg: key C10BDD81: public key "Joshua Tauberer <jt@occams.info>" imported

	$ git verify-tag v0.41
	gpg: Signature made ..... using RSA key ID C10BDD81
	gpg: Good signature from "Joshua Tauberer <jt@occams.info>"
	gpg: WARNING: This key is not certified with a trusted signature!
	gpg:          There is no indication that the signature belongs to the owner.
	Primary key fingerprint: 5F4C 0E73 13CC D744 693B  2AEA B920 41F4 C10B DD81

You'll get a lot of warnings, but that's OK. Check that the primary key fingerprint matches the
fingerprint in the key details at [https://keybase.io/joshdata](https://keybase.io/joshdata)
and on his [personal homepage](https://razor.occams.info/). (Of course, if this repository has been compromised you can't trust these instructions.)

Checkout the tag corresponding to the most recent release:

	$ git checkout v0.41

Begin the installation.

	$ sudo setup/start.sh

For help, DO NOT contact Josh directly --- I don't do tech support by email or tweet (no exceptions).

Post your question on the [discussion forum](https://discourse.mailinabox.email/) instead, where maintainers and Mail-in-a-Box users may be able to help you.

Contributing and Development
----------------------------

Mail-in-a-Box is an open source project. Your contributions and pull requests are welcome. See [CONTRIBUTING](CONTRIBUTING.md) to get started. 


The Acknowledgements
--------------------

This project was inspired in part by the ["NSA-proof your email in 2 hours"](http://sealedabstract.com/code/nsa-proof-your-e-mail-in-2-hours/) blog post by Drew Crawford, [Sovereign](https://github.com/sovereign/sovereign) by Alex Payne, and conversations with <a href="https://twitter.com/shevski" target="_blank">@shevski</a>, <a href="https://github.com/konklone" target="_blank">@konklone</a>, and <a href="https://github.com/gregelin" target="_blank">@GregElin</a>.

Mail-in-a-Box is similar to [iRedMail](http://www.iredmail.org/) and [Modoboa](https://github.com/tonioo/modoboa).

The History
-----------

* In 2007 I wrote a relatively popular Mozilla Thunderbird extension that added client-side SPF and DKIM checks to mail to warn users about possible phishing: [add-on page](https://addons.mozilla.org/en-us/thunderbird/addon/sender-verification-anti-phish/), [source](https://github.com/JoshData/thunderbird-spf).
* In August 2013 I began Mail-in-a-Box by combining my own mail server configuration with the setup in ["NSA-proof your email in 2 hours"](http://sealedabstract.com/code/nsa-proof-your-e-mail-in-2-hours/) and making the setup steps reproducible with bash scripts.
* Mail-in-a-Box was a semifinalist in the 2014 [Knight News Challenge](https://www.newschallenge.org/challenge/2014/submissions/mail-in-a-box), but it was not selected as a winner.
* Mail-in-a-Box hit the front page of Hacker News in [April](https://news.ycombinator.com/item?id=7634514) 2014, [September](https://news.ycombinator.com/item?id=8276171) 2014, [May](https://news.ycombinator.com/item?id=9624267) 2015, and [November](https://news.ycombinator.com/item?id=13050500) 2016.
* FastCompany mentioned Mail-in-a-Box a [roundup of privacy projects](http://www.fastcompany.com/3047645/your-own-private-cloud) on June 26, 2015.
