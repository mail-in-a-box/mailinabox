CHANGELOG
=========

in development
--------------

Control panel:

* The local DNS cache is cleared before running the status checks using 'rncd' now rather than restarting 'bind9', which should be faster and wont interrupt other services.

v0.05 (November 18, 2014)
-------------------------

Mail:

* The maximum size of outbound mail sent via webmail and Exchange/ActiveSync has been increased to 128 MB, the same as when using SMTP.
* Spam is no longer wrapped as an attachment inside a scary Spamassassin explanation. The original message is simply moved straight to the Spam folder unchanged.
* There is a new iOS/Mac OS X Configuration Profile link in the control panel which makes it easier to configure IMAP/SMTP/CalDAV/CardDAV on iOS devices and Macs.
* "Domain aliases" can now be configured in the control panel.
* Updated to [Roundcube 1.0.3](http://trac.roundcube.net/wiki/Changelog).
* IMAP/SMTP is now recommended even on iOS devices as Exchange/ActiveSync is terribly buggy.

Control panel:

* Installing an SSL certificate for the primary hostname would cause problems until a restart (services needed to be restarted).
* Installing SSL certificates would fail if /tmp was on a different filesystem.
* Better error messages when installing a SSL certificate fails.
* The local DNS cache is now cleared each time the system status checks are run.
* Documented how to use +tag addressing.
* Minor UI tweaks.

Other:

* Updated to [ownCloud 7.0.3](http://owncloud.org/changelog/).
* The ownCloud API is now exposed properly.
* DNSSEC now works on `.guide` domains now too (RSASHA256).

v0.04 (October 15, 2014)
------------------------

Breaking changes:

* On-disk backups are now retained for a minimum of 3 days instead of 14. Beyond that the user is responsible for making off-site copies.
* IMAP no longer supports the legacy SSLv3 protocol. SSLv3 is now known to be insecure. I don't believe any modern devices will be affected by this. HTTPS and SMTP submission already had SSLv3 disabled.

Control panel:

* The control panel has a new page for installing SSL certificates.
* The control panel has a new page for hosting static websites.
* The control panel now shows mailbox sizes on disk.
* It is now possible to create catch-all aliases from the control panel.
* Many usability improvements in the control panel.

DNS:

* Custom DNS A/AAAA records on subdomains were ignored.
* It is now possible to set up a secondary DNS server.
* DNS zones were updating even when nothing changed.
* Strict SPF and DMARC settings are now set on all subdomains not used for mail.

Security:

* DNSSEC is now supported for the .email TLD which required a different key algorithm.
* Nginx and Postfix now use 2048 bits of DH parameters instead of 1024.

Other:

* Spam filter learning by dragging mail in and out of the Spam folder should hopefully be working now.
* Some things were broken if the machine had an IPv6 address.
* Other things were broken if the machine was on a non-utf8 locale.
* No longer implementing webfinger.
* Removes apache before installing nginx, in case it has been installed by distro.

v0.03 (September 24, 2014)
--------------------------

* Update existing installs of Roundcube.
* Disabled catch-alls pending figuring out how to get users to take precedence.
* Z-Push was not working because in v0.02 we had accidentally moved to a different version.
* Z-Push is now locked to a specific commit so it doesn't change on us accidentally.
* The start script is now symlinked to /usr/local/bin/mailinabox.

v0.02 (September 21, 2014)
--------------------------

* Open the firewall to an alternative SSH port if set.
* Fixed missing dependencies.
* Set Z-Push to use sync command with ownCloud.
* Support more concurrent connections for z-push.
* In the status checks, handle wildcard certificates.
* Show the status of backups in the control panel.
* The control panel can now update a user's password.
* Some usability improvements in the control panel.
* Warn if a SSL cert is expiring in 30 days.
* Use SHA2 to generate CSRs.
* Better logic for determining when to take a full backup.
* Reduce DNS TTL, not that it seems to really matter.
* Add SSHFP DNS records.
* Add an API for setting custom DNS records 
* Update to ownCloud 7.0.2.
* Some things were broken if the machine had an IPv6 address.
* Use a dialogs library to ask users questions during setup.
* Other fixes.

v0.01 (August 19, 2014)
-----------------------

First release.
