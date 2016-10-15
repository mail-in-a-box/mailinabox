CHANGELOG
=========

In Development
--------------

Control panel:

* Remove recommendations for Certificate Providers
* Status checks failed if the system doesn't support iptables
* Add support for SSHFP records when sshd listens on non-standard ports

v0.20 (September 23, 2016)
--------------------------

ownCloud:

* Updated to ownCloud to 8.2.7.

Control Panel:

* Fixed a crash that occurs when there are IPv6 DNS records due to a bug in dnspython 1.14.0.
* Improved the wonky low disk space check.

v0.19b (August 20, 2016)
------------------------

This update corrects a security issue introduced in v0.18.

* A remote code execution vulnerability is corrected in how the munin system monitoring graphs are generated for the control panel. The vulnerability involves an administrative user visiting a carefully crafted URL.

v0.19a (August 18, 2016)
------------------------

This update corrects a security issue in v0.19.

* fail2ban won't start if Roundcube had not yet been used - new installations probably do not have fail2ban running.

v0.19 (August 13, 2016)
-----------------------

Mail:

* Roundcube is updated to version 1.2.1.
* SSLv3 and RC4 are now no longer supported in incoming and outgoing mail (SMTP port 25).

Control panel:

* The users and aliases APIs are now documented on their control panel pages.
* The HSTS header was missing.
* New status checks were added for the ufw firewall.

DNS:

* Add SRV records for CardDAV/CalDAV to facilitate autoconfiguration (e.g. in DavDroid, whose latest version didn't seem to work to configure with entering just a hostname).

System:

* fail2ban jails added for SMTP submission, Roundcube, ownCloud, the control panel, and munin.
* Mail-in-a-Box can now be installed on the i686 architecture.

v0.18c (June 2, 2016)
---------------------

* Domain aliases (and misconfigured aliases/catch-alls with non-existent local targets) would accept mail and deliver it to new mailbox folders on disk even if the target address didn't correspond with an existing mail user, instead of rejecting the mail. This issue was introduced in v0.18.
* The Munin Monitoring link in the control panel now opens a new window.
* Added an undocumented before-backup script.

v0.18b (May 16, 2016)
---------------------

* Fixed a Roundcube user accounts issue introduced in v0.18.

v0.18 (May 15, 2016)
--------------------

ownCloud:

* Updated to ownCloud to 8.2.3 

Mail:

* Roundcube is updated to version 1.1.5 and the Roundcube login screen now says "[hostname] Webmail" instead of "Mail-in-a-Box/Roundcube webmail".
* Fixed a long-standing issue with training the spam filter not working (because of a file permissions issue).

Control panel:

* Munin system monitoring graphs are now zoomable.
* When a reboot is required (due to Ubuntu security updates automatically installed), a Reboot Box button now appears on the System Status Checks page of the control panel.
* It is now possible to add SRV and secondary MX records in the Custom DNS page.
* Other minor fixes.

System:

* The fail2ban recidive jail, which blocks long-duration brute force attacks, now no longer sends the administrator emails (which were not helpful).

Setup:

* The system hostname is now set during setup.
* A swap file is now created if system memory is less than 2GB, 5GB of free disk space is available, and if no swap file yet exists.
* We now install Roundcube from the official GitHub repository instead of our own mirror, which we had previously created to solve problems with SourceForge.
* DKIM was incorrectly set up on machines where "localhost" was defined as something other than "127.0.0.1".

v0.17c (April 1, 2016)
----------------------

This update addresses some minor security concerns and some installation issues.

ownCoud:

* Block web access to the configuration parameters (config.php). There is no immediate impact (see [#776](https://github.com/mail-in-a-box/mailinabox/pull/776)), although advanced users may want to take note.

Mail:

* Roundcube html5_notifier plugin updated from version 0.6 to 0.6.2 to fix Roundcube getting stuck for some people.

Control panel:

* Prevent click-jacking of the management interface by adding HTTP headers.
* Failed login no longer reveals whether an account exists on the system.

Setup:

* Setup dialogs did not appear correctly when connecting to SSH using Putty on Windows.
* We now install Roundcube from our own mirror because Sourceforge's downloads experience frequent intermittant unavailability.

v0.17b (March 1, 2016)
----------------------

ownCloud moved their source code to a new location, breaking our installation script.

v0.17 (February 25, 2016)
-------------------------

Mail:

* Roundcube updated to version 1.1.4.
* When there's a problem delivering an outgoing message, a new 'warning' bounce will come after 3 hours and the box will stop trying after 2 days (instead of 5).
* On multi-homed machines, Postfix now binds to the right network interface when sending outbound mail so that SPF checks on the receiving end will pass.
* Mail sent from addresses on subdomains of other domains hosted by this box would not be DKIM-signed and so would fail DMARC checks by recipients, since version v0.15.

Control panel:

* TLS certificate provisioning would crash if DNS propagation was in progress and a challenge failed; might have shown the wrong error when provisioning fails.
* Backup times were displayed with the wrong time zone.
* Thresholds for displaying messages when the system is running low on memory have been reduced from 30% to 20% for a warning and from 15% to 10% for an error.
* Other minor fixes.

System:

* Backups to some AWS S3 regions broke in version 0.15 because we reverted the version of boto. That's now fixed.
* On low-usage systems, don't hold backups for quite so long by taking a full backup more often.
* Nightly status checks might fail on systems not configured with a default Unicode locale.
* If domains need a TLS certificate and the user hasn't installed one yet using Let's Encrypt, the administrator would get a nightly email with weird interactive text asking them to agree to Let's Encrypt's ToS. Now just say that the provisioning can't be done automatically.
* Reduce the number of background processes used by the management daemon to lower memory consumption.

Setup:

* The first screen now warns users not to install on a machine used for other things.

v0.16 (January 30, 2016)
------------------------

This update primarily adds automatic SSL (now "TLS") certificate provisioning from Let's Encrypt (https://letsencrypt.org/).

Control Panel:

* The SSL certificates (now referred to as "TLS ccertificates") page now supports provisioning free certificates from Let's Encrypt.
* Report free memory usage.
* Fix a crash when the git directory is not checked out to a tag.
* When IPv6 is enabled, check that all domains (besides the system hostname) resolve over IPv6.
* When a domain doesn't resolve to the box, don't bother checking if the TLS certificate is valid.
* Remove rounded border on the menu bar.

Other:

* The Sieve port is now open so tools like the Thunderbird Sieve extension can be used to edit mail filters.
* .be domains now offer DNSSEC options supported by the TLD
* The daily backup will now email the administrator if there is a problem.
* Expiring TLS certificates are now automatically renewed via Let's Encrypt.
* File ownership for installed Roundcube files is fixed.
* Typos fixed.

v0.15a (January 9, 2016)
------------------------

Mail:

* Sending mail through Exchange/ActiveSync (Z-Push) had been broken since v0.14 in some setups. This is now fixed.

v0.15 (January 1, 2016)
-----------------------

Mail:

* Updated Roundcube to version 1.1.3.
* Auto-create aliases for abuse@, as required by RFC2142.
* The DANE TLSA record is changed to use the certificate subject public key rather than the whole certificate, which means the record remains valid after certificate changes (so long as the private key remains the same, which it does for us).

Control panel:

* When IPv6 is enabled, check that system services are accessible over IPv6 too, that the box's hostname resolves over IPv6, and that reverse DNS is setup correctly for IPv6.
* Explanatory text for setting up secondary nameserver is added/fixed.
* DNS checks now have a timeout in case a DNS server is not responding, so the checks don't stall indefinitely.
* Better messages if external DNS is used and, weirdly, custom secondary nameservers are set.
* Add POP to the mail client settings documentation.
* The box's IP address is added to the fail2ban whitelist so that the status checks don't trigger the machine banning itself, which results in the status checks showing services down even though they are running.
* For SSL certificates, rather than asking you what country you are in during setup, ask at the time a CSR is generated. The default system self-signed certificate now omits a country in the subject (it was never needed). The CSR_COUNTRY Mail-in-a-Box setting is dropped entirely.

System:

* Nightly backups and system status checks are now moved to 3am in the system's timezone.
* fail2ban's recidive jail is now active, which guards against persistent brute force login attacks over long periods of time.
* Setup (first run only) now asks for your timezone to set the system time.
* The Exchange/ActiveSync server is now taken offline during nightly backups (along with SMTP and IMAP).
* The machine's random number generator (/dev/urandom) is now seeded with Ubuntu Pollinate and a blocking read on /dev/random.
* DNSSEC key generation during install now uses /dev/urandom (instead of /dev/random), which is faster.
* The $STORAGE_ROOT/ssl directory is flattened by a migration script and the system SSL certificate path is now a symlink to the actual certificate.
* If ownCloud sends out email, it will use the box's administrative address now (admin@yourboxname).
* Z-Push (Exchange/ActiveSync) logs now exclude warnings and are now rotated to save disk space.
* Fix pip command that might have not installed all necessary Python packages.
* The control panel and backup would not work on Google Compute Engine because GCE installs a conflicting boto package.
* Added a new command `management/backup.py --restore` to restore files from a backup to a target directory (command line arguments are passed to `duplicity restore`).

v0.14 (November 4, 2015)
------------------------

Mail:

* Spamassassin's network-based tests (Pyzor, others) and DKIM tests are now enabled. (Pyzor had always been installed but was not active due to a misconfiguration.)
* Moving spam out of the Spam folder and into Trash would incorrectly train Spamassassin that those messages were not spam.
* Automatically create the Sent and Archive folders for new users.
* The HTML5_Notifier plugin for Roundcube is now included, which when turned on in Roundcube settings provides desktop notifications for new mail.
* The Exchange/ActiveSync backend Z-Push has been updated to fix a problem with CC'd emails not being sent to the CC recipients.

Calender/Contacts:

* CalDAV/CardDAV and Exchange/ActiveSync for calendar/contacts wasn't working in some network configurations.

Web:

* When a new domain is added to the box, rather than applying a new self-signed certificate for that domain, the SSL certificate for the box's primary hostname will be used instead.
* If a custom DNS record is set on a domain or 'www'+domain, web would not be served for that domain. If the custom DNS record is just the box's IP address, that's a configuration mistake, but allow it and let web continue to be served.
* Accommodate really long domain names by increasing an nginx setting.

Control panel:

* Added an option to check for new Mail-in-a-Box versions within status checks. It is off by default so that boxes don't "phone home" without permission.
* Added a random password generator on the users page to simplify creating new accounts.
* When S3 backup credentials are set, the credentials are now no longer ever sent back from the box to the client, for better security.
* Fixed the jumpiness when a modal is displayed.
* Focus is put into the login form fields when the login form is displayed.
* Status checks now include a warning if a custom DNS record has been set on a domain that would normally serve web and as a result that domain no longer is serving web.
* Status checks now check that secondary nameservers, if specified, are actually serving the domains.
* Some errors in the control panel when there is invalid data in the database or an improperly named archived user account have been suppressed.
* Added subresource integrity attributes to all remotely-sourced resources (i.e. via CDNs) to guard against CDNs being used as an attack vector.

System:

* Tweaks to fail2ban settings.
* Fixed a spurrious warning while installing munin.

v0.13b (August 30, 2015)
------------------------

Another ownCloud 8.1.1 issue was found. New installations left ownCloud improperly setup ("You are accessing the server from an untrusted domain."). Upgrading to this version will fix that.

v0.13a (August 23, 2015)
------------------------

Note: v0.13 (no 'a', August 19, 2015) was pulled immediately due to an ownCloud bug that prevented upgrades. v0.13a works around that problem.

Mail:

* Outbound mail headers (the Recieved: header) are tweaked to possibly improve deliverability.
* Some MIME messages would hang Roundcube due to a missing package.
* The users permitted to send as an alias can now be different from where an alias forwards to.

DNS:

* The secondary nameservers option in the control panel now accepts more than one nameserver and a special xfr:IP format to specify zone-transfer-only IP addresses.
* A TLSA record is added for HTTPS for DNSSEC-aware clients that support it.

System:

* Backups can now be turned off, or stored in Amazon S3, through new control panel options.
* Munin was not working on machines confused about their hostname and had lots of errors related to PANGO, NTP peers and network interfaces that were not up.
* ownCloud updated to version 8.1.1 (with upgrade work-around), its memcached caching enabled.
* When upgrading, network checks like blocked port 25 are now skipped.
* Tweaks to the intrusion detection rules for IMAP.
* Mail-in-a-Box's setup is a lot quieter, hiding lots of irrelevant messages.

Control panel:

* SSL certificate checks were failing on OVH/OpenVZ servers due to missing /dev/stdin.
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

First versioned release after a year of unversioned development.
