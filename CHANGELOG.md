CHANGELOG
=========

To-be-released
--------------

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
