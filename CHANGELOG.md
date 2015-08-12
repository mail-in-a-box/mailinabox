CHANGELOG
=========

In Development
--------------

Mail:

* Outbound mail headers (the Recieved: header) are tweaked to possibly improve deliverability.
* Some MIME messages would hang Roundcube due to a missing package.

DNS:

* The secondary nameservers option in the control panel now accepts more than one nameserver and a special xfr:IP format to specify zone-transfer-only IP addresses.
* A TLSA record is added for HTTPS for DNSSEC-aware clients that support it.

System:

* Backups can now be turned off, or stored in Amazon S3, through new control panel options.
* Munin was not working on machines confused about their hostname.
* ownCloud updated to version 8.1.1.
* When upgrading, network checks like blocked port 25 are now skipped.
* Tweaks to the intrusion detection rules for IMAP.
* Improve the sort order of the domains in the status checks.
* Some links in the control panel were only working in Chrome.

v0.12c (July 19, 2015)
----------------------

v0.12c was posted to work around the current Sourceforge.net outage: pyzor's remote server is now hard-coded rather than accessing a file hosted on Sourceforge, and roundcube is now downloaded from a Mail-in-a-Box mirror rather than from Sourceforge.

v0.12b (July 4, 2015)
---------------------

This version corrects a minor regression in v0.12 related to creating aliases targetting multiple addresses.

v0.12 (July 3, 2015)
--------------------

This is a minor update to v0.11, which was a major update. Please read v0.11's advisories.

* The administrator@ alias was incorrectly created starting with v0.11. If your first install was v0.11, check that the administrator@ alias forwards mail to you.
* Intrusion detection rules (fail2ban) are relaxed (i.e. less is blocked).
* SSL certificates could not be installed for the new automatic 'www.' redirect domains.
* PHP's default character encoding is changed from no default to UTF8. The effect of this change is unclear but should prevent possible future text conversion issues.
* User-installed SSL private keys in the BEGIN PRIVATE KEY format were not accepted.
* SSL certificates with SAN domains with IDNA encoding were broken in v0.11.
* Some IDNA functionality was using IDNA 2003 rather than IDNA 2008.

v0.11b (June 29, 2015)
----------------------

v0.11b was posted shortly after the initial posting of v0.11 to correct a missing dependency for the new PPA.

v0.11 (June 29, 2015)
---------------------

Advisories:
* Users can no longer spoof arbitrary email addresses in outbound mail. When sending mail, the email address configured in your mail client must match the SMTP login username being used, or the email address must be an alias with the SMTP login username listed as one of the alias's targets.
* This update replaces your DKIM signing key with a stronger key. Because of DNS caching/propagation, mail sent within a few hours after this update could be marked as spam by recipients. If you use External DNS, you will need to update your DNS records.
* The box will now install software from a new Mail-in-a-Box PPA on Launchpad.net, where we are distributing two of our own packages: a patched postgrey and dovecot-lucene.

Mail:
* Greylisting will now let some reputable senders pass through immediately.
* Searching mail (via IMAP) will now be much faster using the dovecot lucene full text search plugin.
* Users can no longer spoof arbitrary email addresses in outbound mail (see above).
* Fix for deleting admin@ and postmaster@ addresses.
* Roundcube is updated to version 1.1.2, plugins updated.
* Exchange/ActiveSync autoconfiguration was not working on all devices (e.g. iPhone) because of a case-sensitive URL.
* The DKIM signing key has been increased to 2048 bits, from 1024, replacing the existing key.

Web:
* 'www' subdomains now automatically redirect to their parent domain (but you'll need to install an SSL certificate).
* OCSP no longer uses Google Public DNS.
* The installed PHP version is no longer exposed through HTTP response headers, for better security.

DNS:
* Default IPv6 AAAA records were missing since version 0.09.

Control panel:
* Resetting a user's password now forces them to log in again everywhere.
* Status checks were not working if an ssh server was not installed.
* SSL certificate validation now uses the Python cryptography module in some places where openssl was used.
* There is a new tab to show the installed version of Mail-in-a-Box and to fetch the latest released version.

System:
* The munin system monitoring tool is now installed and accessible at /admin/munin.
* ownCloud updated to version 8.0.4. The ownCloud installation step now is reslient to download problems. The ownCloud configuration file is now stored in STORAGE_ROOT to fix loss of data when moving STORAGE_ROOT to a new machine.
* The setup scripts now run `apt-get update` prior to installing anything to ensure the apt database is in sync with the packages actually available.


v0.10 (June 1, 2015)
--------------------

* SMTP Submission (port 587) began offering the insecure SSLv3 protocol due to a misconfiguration in the previous version.
* Roundcube now allows persistent logins using Roundcube-Persistent-Login-Plugin.
* ownCloud is updated to version 8.0.3.
* SPF records for non-mail domains were tightened.
* The minimum greylisting delay has been reduced from 5 minutes to 3 minutes.
* Users and aliases weren't working if they were entered with any uppercase letters. Now only lowercase is allowed.
* After installing an SSL certificate from the control panel, the page wasn't being refreshed.
* Backups broke if the box's hostname was changed after installation.
* Dotfiles (i.e. .svn) stored in ownCloud Files were not accessible from ownCloud's mobile/desktop clients.
* Fix broken install on OVH VPS's.


v0.09 (May 8, 2015)
-------------------

Mail:

* Spam checking is now performed on messages larger than the previous limit of 64KB.
* POP3S is now enabled (port 995).
* Roundcube is updated to version 1.1.1.
* Minor security improvements (more mail headers with user agent info are anonymized; crypto settings were tightened).

ownCloud:

* Downloading files you uploaded to ownCloud broke because of a change in ownCloud 8.

DNS:

* Internationalized Domain Names (IDNs) should now work in email. If you had custom DNS or custom web settings for internationalized domains, check that they are still working.
* It is now possible to set multiple TXT and other types of records on the same domain in the control panel.
* The custom DNS API was completely rewritten to support setting multiple records of the same type on a domain. Any existing client code using the DNS API will have to be rewritten. (Existing code will just get 404s back.)
* On some systems the `nsd` service failed to start if network inferfaces were not ready.

System / Control Panel:

* In order to guard against misconfiguration that can lead to domain control validation hijacking, email addresses that begin with admin, administrator, postmaster, hostmaster, and webmaster can no longer be used for (new) mail user accounts, and aliases for these addresses may direct mail only to the box's administrator(s).
* Backups now use duplicity's built-in gpg symmetric AES256 encryption rather than my home-brewed encryption. Old backups will be incorporated inside the first backup after this update but then deleted from disk (i.e. your backups from the previous few days will be backed up).
* There was a race condition between backups and the new nightly status checks.
* The control panel would sometimes lock up with an unnecessary loading indicator.
* You can no longer delete your own account from the control panel.

Setup:

* All Mail-in-a-Box release tags are now signed on github, instructions for verifying the signature are added to the README, and the integrity of some packages downloaded during setup is now verified against a SHA1 hash stored in the tag itself.
* Bugs in first user account creation were fixed.

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
