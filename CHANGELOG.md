CHANGELOG
=========

In Development
--------------

Mail:

* Spam checking is now performed on messages larger than the previous limit of 64KB.
* POP3S is now enabled (port 995).
* In order to guard against misconfiguration that can lead to domain control validation hijacking, email addresses that begin with admin, administrator, postmaster, hostmaster, and webmaster can no longer be used for (new) mail user accounts, and aliases for these addresses may direct mail only to the box's administrator(s).

System:

* Internationalized Domain Names (IDNs) should now work in email. If you had custom DNS or custom web settings for internationalized domains, check that they are still working.


v0.08 (April 1, 2015)
---------------------

Mail:

* The Roundcube vacation_sieve plugin by @arodier is now installed to make it easier to set vacation auto-reply messages from within Roundcube.
* Authentication-Results headers for DMARC, added in v0.07, were mistakenly added for outbound mail --- that's now removed.
* The Trash folder is now created automatically for new mail accounts, addressing a Roundcube error.

DNS:

* Custom DNS TXT records were not always working and they can now override the default SPF, DKIM, and DMARC records.

System:

* ownCloud updated to version 8.0.2.
* Brute-force SSH and IMAP login attempts are now prevented by properly configuring fail2ban.
* Status checks are run each night and any changes from night to night are emailed to the box administrator (the first user account).

Control panel:

* The new check that system services are running mistakenly checked that the Dovecot Managesieve service is publicly accessible. Although the service binds to the public network interface we don't open the port in ufw. On some machines it seems that ufw blocks the connection from the status checks (which seems correct) and on some machines (mine) it doesn't, which is why I didn't notice the problem.
* The current backup chain will now try to predict how many days until it is deleted (always at least 3 days after the next full backup).
* The list of aliases that forward to a user are removed from the Mail Users page because when there are many alises it is slow and times-out.
* Some status check errors are turned into warnings, especially those that might not apply if External DNS is used.

v0.07 (February 28, 2015)
-------------------------

Mail:

* If the box manages mail for a domain and a subdomain of that domain, outbound mail from the subdomain was not DKIM-signed and would therefore fail DMARC tests on the receiving end, possibly result in the mail heading into spam folders.
* Auto-configuration for Mozilla Thunderbird, Evolution, KMail, and Kontact is now available.
* Domains that only have a catch-all alias or domain alias no longer automatically create/require admin@ and postmaster@ addresses since they'll forward anyway.
* Roundcube is updated to version 1.1.0.
* Authentication-Results headers for DMARC are now added to incoming mail.

DNS:

* If a custom CNAME record is set on a 'www' subdomain, the default A/AAAA records were preventing the CNAME from working.
* If a custom DNS A record overrides one provided by the box, the a corresponding default IPv6 record by the box is removed since it will probably be incorrect.
* Internationalized domain names (IDNs) are now supported for DNS and web, but email is not yet tested.

Web:

* Static websites now deny access to certain dot (.) files and directories which typically have sensitive info: .ht*, .svn*, .git*, .hg*, .bzr*.
* The nginx server no longer reports its version and OS for better privacy.
* The HTTP->HTTPS redirect is now more efficient.
* When serving a 'www.' domain, reuse the SSL certificate for the parent domain if it covers the 'www' subdomain too
* If a custom DNS CNAME record is set on a domain, don't offer to put a website on that domain. (Same logic already applies to custom A/AAAA records.)

Control panel:

* Status checks now check that system services are actually running by pinging each port that should have something running on it.
* The status checks are now parallelized so they may be a little faster.
* The status check for MX records now allow any priority, in case an unusual setup is required.
* The interface for setting website domain-specific directories is simplified.
* The mail guide now says that to use Outlook, Outlook 2007 or later on Windows 7 and later is required.
* External DNS settings now skip the special "_secondary_nameserver" key which is used for storing secondary NS information.

Setup:

* Install cron if it isn't already installed.
* Fix a units problem in the minimum memory check.
* If you override the STORAGE_ROOT, your setting will now persist if you re-run setup.
* Hangs due to apt wanting the user to resolve a conflict should now be fixed (apt will just clobber the problematic file now).

v0.06 (January 4, 2015)
-----------------------

Mail:

* Set better default system limits to accommodate boxes handling mail for 20+ users.

Contacts/calendar:

* Update to ownCloud to 7.0.4.
* Contacts syncing via ActiveSync wasn't working.

Control panel:

* New control panel for setting custom DNS settings (without having to use the API).
* Status checks showed a false positive for Spamhause blacklists and for secondary DNS in some cases.
* Status checks would fail to load if openssh-sever was not pre-installed, but openssh-server is not required.
* The local DNS cache is cleared before running the status checks using 'rncd' now rather than restarting 'bind9', which should be faster and wont interrupt other services.
* Multi-domain and wildcard certificate can now be installed through the control panel.
* The DNS API now allows the setting of SRV records.

Misc:

* IPv6 configuration error in postgrey, nginx.
* Missing dependency on sudo.

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
