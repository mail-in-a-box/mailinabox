# CHANGELOG

## Next

-   Place PHP version into a global variable

## Version 66 (December 17, 2023)

-   Some users reported an error installing Mail-in-a-Box related to the virtualenv command. This is hopefully fixed.
-   Roundcube is updated to 1.6.5 fixing a security vulnerability.
-   For Mail-in-a-Box developers, a new setup variable is added to pull the source code from a different repository.

## Version 65 (October 27, 2023)

-   Roundcube updated to 1.6.4 fixing a security vulnerability.
-   zpush.sh updated to version 2.7.1.
-   Fixed a typo in the control panel.

## Version 64 (September 2, 2023)

-   Fixed broken installation when upgrading from Mail-in-a-Box version 56 (Nextcloud 22) and earlier because of an upstream packaging issue.
-   Fixed backups to work with the latest duplicity package which was not backwards compatible.
-   Fixed setting B2 as a backup target with a slash in the application key.
-   Turned off OpenDMARC diagnostic reports sent in response to incoming mail.
-   Fixed some crashes when using an unrelased version of Mail-in-a-Box.
-   Added z-push administration scripts.

## Version 63 (July 27, 2023)

-   Nextcloud updated to 25.0.7.

## Version 62 (May 20, 2023)

Package updates:

-   Nextcloud updated to 23.0.12 (and its apps also updated).
-   Roundcube updated to 1.6.1.
-   Z-Push to 2.7.0, which has compatibility for Ubuntu 22.04, so it works again.

Mail:

-   Roundcube’s password change page is now working again.

Control panel:

-   Allow setting the backup location’s S3 region name for non-AWS S3-compatible backup hosts.
-   Control panel pages can be opened in a new tab/window and bookmarked and browser history navigation now works.
-   Add a Copy button to put the rsync backup public key on clipboard.
-   Allow secondary DNS xfr: items added in the control panel to be hostnames too.
-   Fixed issue where sshkeygen fails when IPv6 is disabled.
-   Fixed issue opening munin reports.
-   Fixed report formatting in status emails sent to the administrator.

## Version 61.1 (January 28, 2023)

-   Fixed rsync backups not working with the default port.
-   Reverted “Improve error messages in the management tools when external command-line tools are run.” because of the possibility of user secrets being included in error messages.
-   Fix for TLS certificate SHA fingerprint not being displayed during setup.

## Version 61 (January 21, 2023)

System:

-   fail2ban didn’t start after setup.

Mail:

-   Disable Roundcube password plugin since it was corrupting the user database.

Control panel:

-   Fix changing existing backup settings when the rsync type is used.
-   Allow setting a custom port for rsync backups.
-   Fixes to DNS lookups during status checks when there are timeouts, enforce timeouts better.
-   A new check is added to ensure fail2ban is running.
-   Fixed a color.
-   Improve error messages in the management tools when external command-line tools are run.

## Version 60.1 (October 30, 2022)

-   A setup issue where the DNS server nsd isn’t running at the end of setup is (hopefully) fixed.
-   Nextcloud is updated to 23.0.10 (contacts to 4.2.2, calendar to 3.5.1).

## Version 60 (October 11, 2022)

This is the first release for Ubuntu 22.04.

**Before upgrading**, you must **first upgrade your existing Ubuntu 18.04 box to Mail-in-a-Box v0.51 or later**, if you haven’t already done so. That may not be possible after Ubuntu 18.04 reaches its end of life in April 2023, so please complete the upgrade well before then. (If you are not using Nextcloud’s contacts or calendar, you can migrate to the latest version of Mail-in-a-Box from any previous version.)

For complete upgrade instructions, see:

https://discourse.mailinabox.email/t/version-60-for-ubuntu-22-04-is-about-to-be-released/9558

No major features of Mail-in-a-Box have changed in this release, although some minor fixes were made.

With the newer version of Ubuntu the following software packages we use are updated:

-   dovecot is upgraded to 2.3.16, postfix to 3.6.4, opendmark to 1.4 (which adds ARC-Authentication-Results headers), and spampd to 2.53 (alleviating a mail delivery rate limiting bug).
-   Nextcloud is upgraded to 23.0.4 (contacts to 4.2.0, calendar to 3.5.0).
-   Roundcube is upgraded to 1.6.0.
-   certbot is upgraded to 1.21 (via the Ubuntu repository instead of a PPA).
-   fail2ban is upgraded to 0.11.2.
-   nginx is upgraded to 1.18.
-   PHP is upgraded from 7.2 to 8.0.

Also:

-   Roundcube’s login session cookie was tightened. Existing sessions may require a manual logout.
-   Moved Postgrey’s database under $STORAGE_ROOT.

## Version 57a (June 19, 2022)

-   The Backblaze backups fix posted in Version 57 was incomplete. It’s now fixed.

## Version 57 (June 12, 2022)

Setup:

-   Fixed issue upgrading from Mail-in-a-Box v0.40-v0.50 because of a changed URL that Nextcloud is downloaded from.

Backups:

-   Fixed S3 backups which broke with duplicity 0.8.23.
-   Fixed Backblaze backups which broke with latest b2sdk package by rolling back its version.

Control panel:

-   Fixed spurious changes in system status checks messages by sorting DNSSEC DS records.
-   Fixed fail2ban lockout over IPv6 from excessive loads of the system status checks.
-   Fixed an incorrect IPv6 system status check message.

## Version 56 (January 19, 2022)

Software updates:

-   Roundcube updated to 1.5.2 (from 1.5.0), and the persistent_login and CardDAV (to 4.3.0 from 3.0.3) plugins are updated.
-   Nextcloud updated to 20.0.14 (from 20.0.8), contacts to 4.0.7 (from 3.5.1), and calendar to 3.0.4 (from 2.2.0).

Setup:

-   Fixed failed setup if a previous attempt failed while updating Nextcloud.

Control panel:

-   Fixed a crash if a custom DNS entry is not under a zone managed by the box.
-   Fix DNSSEC instructions typo.

Other:

-   Set systemd journald log retention to 10 days (from no limit) to reduce disk usage.
-   Fixed log processing for submission lines that have a sasl_sender or other extra information.
-   Fix DNS secondary nameserver refesh failure retry period.

## Version 55 (October 18, 2021)

Mail:

-   “SMTPUTF8” is now disabled in Postfix. Because Dovecot still does not support SMTPUTF8, incoming mail to internationalized addresses was bouncing. This fixes incoming mail to internationalized domains (which was probably working prior to v0.40), but it will prevent sending outbound mail to addresses with internationalized local-parts.
-   Upgraded to Roundcube 1.5.

Control panel:

-   The control panel menus are now hidden before login, but now non-admins can log in to access the mail and contacts/calendar instruction pages.
-   The login form now disables browser autocomplete in the two-factor authentication code field.
-   After logging in, the default page is now a fast-loading welcome page rather than the slow-loading system status checks page.
-   The backup retention period option now displays for B2 backup targets.
-   The DNSSEC DS record recommendations are cleaned up and now recommend changing records that use SHA1.
-   The Munin monitoring pages no longer require a separate HTTP basic authentication login and can be used if two-factor authentication is turned on.
-   Control panel logins are now tied to a session backend that allows true logouts (rather than an encrypted cookie).
-   Failed logins no longer directly reveal whether the email address corresponds to a user account.
-   Browser dark mode now inverts the color scheme.

Other:

-   Fail2ban’s IPv6 support is enabled.
-   The mail log tool now doesn’t crash if there are email addresess in log messages with invalid UTF-8 characters.
-   Additional nsd.conf files can be placed in /etc/nsd.conf.d.

## v0.54 (June 20, 2021)

Mail:

-   Forwarded mail using mail filter rules (in Roundcube; “sieve” rules) stopped re-writing the envelope address at some point, causing forwarded mail to often be marked as spam by the final recipient. These forwards will now re-write the envelope as the Mail-in-a-Box user receiving the mail to comply with SPF/DMARC rules.
-   Sending mail is now possible on port 465 with the “SSL” or “TLS” option in mail clients, and this is now the recommended setting. Port 587 with STARTTLS remains available but should be avoided when configuring new mail clients.
-   Roundcube’s login cookie is updated to use a new encryption algorithm (AES-256-CBC instead of DES-EDE-CBC).

DNS:

-   The ECDSAP256SHA256 DNSSEC algorithm is now available. If a DS record is set for any of your domain names that have DNS hosted on your box, you will be prompted by status checks to update the DS record at your convenience.
-   Null MX records are added for domains that do not serve mail.

Contacts/calendar:

-   Updated Nextcloud to 20.0.8, contacts to 3.5.1, calendar to 2.2.0 (#1960).

Control panel:

-   Fixed a crash in the status checks.
-   Small wording improvements.

Setup:

-   Minor improvements to the setup scripts.

## v0.53a (May 8, 2021)

The download URL for Z-Push has been revised becaue the old URL stopped working.

## v0.53 (April 12, 2021)

Software updates:

-   Upgraded Roundcube to version 1.4.11 addressing a security issue, and its desktop notifications plugin.
-   Upgraded Z-Push (for Exchange/ActiveSync) to version 2.6.2.

Control panel:

-   Backblaze B2 is now a supported backup protocol.
-   Fixed an issue in the daily mail reports.
-   Sort the Custom DNS by zone and qname, and add an option to go back to the old sort order (creation order).

Mail:

-   Enable sending DMARC failure reports to senders that request them.

Setup:

-   Fixed error when upgrading from Nextcloud 13.

## v0.52 (January 31, 2021)

Software updates:

-   Upgraded Roundcube to version 1.4.10.
-   Upgraded Z-Push to 2.6.1.

Mail:

-   Incoming emails with SPF/DKIM/DMARC failures now get a higher spam score, and these messages are more likely to appear in the junk folder, since they are often spam/phishing.
-   Fixed the MTA-STS policy file’s line endings.

Control panel:

-   A new Download button in the control panel’s External DNS page can be used to download the required DNS records in zonefile format.
-   Fixed the problem when the control panel would report DNS entries as Not Set by increasing a bind query limit.
-   Fixed a control panel startup bug on some systems.
-   Improved an error message on a DNS lookup timeout.
-   A typo was fixed.

DNS:

-   The TTL for NS records has been increased to 1 day to comply with some registrar requirements.

System:

-   Nextcloud’s photos, dashboard, and activity apps are disabled since we only support contacts and calendar.

## v0.51 (November 14, 2020)

Software updates:

-   Upgraded Nextcloud from 17.0.6 to 20.0.1 (with Contacts from 3.3.0 to 3.4.1 and Calendar from 2.0.3 to 2.1.2)
-   Upgraded Roundcube to version 1.4.9.

Mail:

-   The MTA-STA max_age value was increased to the normal one week.

Control panel:

-   Two-factor authentication can now be enabled for logins to the control panel. However, keep in mind that many online services (including domain name registrars, cloud server providers, and TLS certificate providers) may allow an attacker to take over your account or issue a fraudulent TLS certificate with only access to your email address, and this new two-factor authentication does not protect access to your inbox. It therefore remains very important that user accounts with administrative email addresses have strong passwords.
-   TLS certificate expiry dates are now shown in ISO8601 format for clarity.

## v0.50 (September 25, 2020)

Setup:

-   When upgrading from versions before v0.40, setup will now warn that ownCloud/Nextcloud data cannot be migrated rather than failing the installation.

Mail:

-   An MTA-STS policy for incoming mail is now published (in DNS and over HTTPS) when the primary hostname and email address domain both have a signed TLS certificate installed, allowing senders to know that an encrypted connection should be enforced.
-   The per-IP connection limit to the IMAP server has been doubled to allow more devices to connect at once, especially with multiple users behind a NAT.

DNS:

-   autoconfig and autodiscover subdomains and CalDAV/CardDAV SRV records are no longer generated for domains that don’t have user accounts since they are unnecessary.
-   IPv6 addresses can now be specified for secondary DNS nameservers in the control panel.

TLS:

-   TLS certificates are now provisioned in groups by parent domain to limit easy domain enumeration and make provisioning more resilient to errors for particular domains.

Control panel:

-   The control panel API is now fully documented at https://mailinabox.email/api-docs.html.
-   User passwords can now have spaces.
-   Status checks for automatic subdomains have been moved into the section for the parent domain.
-   Typo fixed.

Web:

-   The default web page served on fresh installations now adds the `noindex` meta tag.
-   The HSTS header is revised to also be sent on non-success responses.

## v0.48 (August 26, 2020)

Security fixes:

-   Roundcube is updated to version 1.4.8 fixing additional cross-site scripting (XSS) vulnerabilities.

## v0.47 (July 29, 2020)

Security fixes:

-   Roundcube is updated to version 1.4.7 fixing a cross-site scripting (XSS) vulnerability with HTML messages with malicious svg/namespace (CVE-2020-15562) (https://roundcube.net/news/2020/07/05/security-updates-1.4.7-1.3.14-and-1.2.11).
-   SSH connections are now rate-limited at the firewall level (in addition to fail2ban).

## v0.46 (June 11, 2020)

Security fixes:

-   Roundcube is updated to version 1.4.6 (https://roundcube.net/news/2020/06/02/security-updates-1.4.5-and-1.3.12).

## v0.45 (May 16, 2020)

Security fixes:

-   Fix missing brute force login protection for Roundcube logins.

Software updates:

-   Upgraded Roundcube from 1.4.2 to 1.4.4.
-   Upgraded Nextcloud from 17.0.2 to 17.0.6 (with Contacts from 3.1.6 to 3.3.0 and Calendar from 1.7.1 to v2.0.3)
-   Upgraded Z-Push to 2.5.2.

System:

-   Nightly backups now occur on a random minute in the 3am hour (in the system time zone). The minute is chosen during Mail-in-a-Box installation/upgrade and remains the same until the next upgrade.
-   Fix for mail log statistics report on leap days.
-   Fix Mozilla autoconfig useGlobalPreferredServer setting.

Web:

-   Add a new hidden feature to set nginx alias in www/custom.yaml.

Setup:

-   Improved error handling.

## v0.44 (February 15, 2020)

System:

-   TLS settings have been upgraded following Mozilla’s recommendations for servers. TLS1.2 and 1.3 are now the only supported protocols for web, IMAP, and SMTP (submission).
-   Fixed an issue starting services when Mail-in-a-Box isn’t on the root filesystem.
-   Changed some performance options affecting Roundcube and Nextcloud.

Software updates:

-   Upgraded Nextcloud from 15.0.8 to 17.0.2 (with Contacts from 3.1.1 to 3.1.6 and Calendar from 1.6.5 to 1.7.1)
-   Upgraded Z-Push to 2.5.1.
-   Upgraded Roundcube from 1.3.10 to 1.4.2 and changed the default skin (theme) to Elastic.

Control panel:

-   The Custom DNS list of records is now sorted.
-   The emails that report TLS provisioning results now has a less scary subject line.

Mail:

-   Fetching of updated whitelist for greylisting was fetching each day instead of every month.
-   OpenDKIM signing has been changed to ‘relaxed’ mode so that some old mail lists that forward mail can do so.

DNS:

-   Automatic autoconfig.\* subdomains can now be suppressed with custom DNS records.
-   DNS zone transfer now works with IPv6 addresses.

Setup:

-   An Ubuntu package source was missing on systems where it defaults off.

## v0.43 (September 1, 2019)

Security fixes:

-   A security issue was discovered in rsync backups. If you have enabled rsync backups, the file `id_rsa_miab` may have been copied to your backup destination. This file can be used to access your backup destination. If the file was copied to your backup destination, we recommend that you delete the file on your backup destination, delete `/root/.ssh/id_rsa_miab` on your Mail-in-a-Box, then re-run Mail-in-a-Box setup, and re-configure your SSH public key at your backup destination according to the instructions in the Mail-in-a-Box control panel.
-   Brute force attack prevention was missing for the managesieve service.

Setup:

-   Nextcloud was not upgraded properly after restoring Mail-in-a-Box from a backup from v0.40 or earlier.

Mail:

-   Upgraded Roundcube to 1.3.10.
-   Fetch an updated whitelist for greylisting on a monthly basis to reduce the number of delayed incoming emails.

Control panel:

-   When using secondary DNS, it is now possible to specify a subnet range with the `xfr:` option.
-   Fixed an issue when the secondary DNS option is used and the secondary DNS hostname resolves to multiple IP addresses.
-   Fix a bug in how a backup configuration error is shown.

## v0.42b (August 3, 2019)

Changes:

-   Decreased the minimum supported RAM to 502 Mb.
-   Improved mail client autoconfiguration.
-   Added support for S3-compatible backup services besides Amazon S3.
-   Fixed the control panel login page to let LastPass save passwords.
-   Fixed an error in the user privileges API.
-   Silenced some spurrious messages.

Software updates:

-   Upgraded Roundcube from 1.3.8 to 1.3.9.
-   Upgraded Nextcloud from 14.0.6 to 15.0.8 (with Contacts from 2.1.8 to 3.1.1 and Calendar from 1.6.4 to 1.6.5).
-   Upgraded Z-Push from 2.4.4 to 2.5.0.

Note that v0.42 (July 4, 2019) was pulled shortly after it was released to fix a Nextcloud upgrade issue.

## v0.41 (February 26, 2019)

System:

-   Missing brute force login attack prevention (fail2ban) filters which stopped working on Ubuntu 18.04 were added back.
-   Upgrades would fail if Mail-in-a-Box moved to a different directory in `systemctl link`.

Mail:

-   Incoming messages addressed to more than one local user were rejected because of a bug in spampd packaged by Ubuntu 18.04. A workaround was added.

Contacts/Calendar:

-   Upgraded Nextcloud from 13.0.6 to 14.0.6.
-   Upgraded Contacts from 2.1.5 to 2.1.8.
-   Upgraded Calendar from 1.6.1 to 1.6.4.

## v0.40 (January 12, 2019)

This is the first release for Ubuntu 18.04. This version and versions going forward can **only** be installed on Ubuntu 18.04; however, upgrades of existing Ubuntu 14.04 boxes to the latest version supporting Ubuntu 14.04 (v0.30) continue to work as normal.

When **upgrading**, you **must first upgrade your existing Ubuntu 14.04 Mail-in-a-Box box** to the latest release supporting Ubuntu 14.04 --- that’s v0.30 --- before you migrate to Ubuntu 18.04. If you are running an older version of Mail-in-a-Box which has an old version of ownCloud or Nextcloud, you will _not_ be able to upgrade your data because older versions of ownCloud and Nextcloud that are required to perform the upgrade _cannot_ be run on Ubuntu 18.04. To upgrade from Ubuntu 14.04 to Ubuntu 18.04, you **must create a fresh Ubuntu 18.04 machine** before installing this version. In-place upgrades of servers are not supported. Since Ubuntu’s support for Ubuntu 14.04 has almost ended, everyone is encouraged to create a new Ubuntu 18.04 machine and migrate to it.

For complete upgrade instructions, see:

https://discourse.mailinabox.email/t/mail-in-a-box-version-v0-40-and-moving-to-ubuntu-18-04/4289

The changelog for this release follows.

Setup:

-   Mail-in-a-Box now targets Ubuntu 18.04 LTS, which will have support from Ubuntu through 2022.
-   Some of the system packages updated in virtue of using Ubuntu 18.04 include postfix (2.11=>3.3) nsd (4.0=>4.1), nginx (1.4=>1.14), PHP (7.0=>7.2), Python (3.4=>3.6), fail2ban (0.8=>0.10), Duplicity (0.6=>0.7).
-   [Unofficial Bash Strict Mode](http://redsymbol.net/articles/unofficial-bash-strict-mode/) is turned on for setup, which might catch previously uncaught issues during setup.

Mail:

-   IMAP server-side full text search is no longer supported because we were using a custom-built `dovecot-lucene` package that we are no longer maintaining.
-   Sending email is now disabled on port 25 --- you must log in to port 587 to send email, per the long-standing mail instructions.
-   Greylisting may delay more emails from new senders. We were using a custom-built postgrey package previously that whitelisted sending domains in dnswl.org, but we are no longer maintaining that package.

## v0.30 (January 9, 2019)

Setup:

-   Update to Roundcube 1.3.8 and the CardDAV plugin to 3.0.3.
-   Add missing rsyslog package to install line since some OS images don’t have it installed by default.
-   A log file for nsd was added.

Control Panel:

-   The users page now documents that passwords should only have ASCII characters to prevent character encoding mismaches between clients and the server.
-   The users page no longer shows user mailbox sizes because this was extremely slow for very large mailboxes.
-   The Mail-in-a-Box version is now shown in the system status checks even when the new-version check is disabled.
-   The alises page now warns that alises should not be used to forward mail off of the box. Mail filters within Roundcube are better for that.
-   The explanation of greylisting has been improved.

## v0.29 (October 25, 2018)

-   Starting with v0.28, TLS certificate provisioning wouldn’t work on new boxes until the mailinabox setup command was run a second time because of a problem with the non-interactive setup.
-   Update to Nextcloud 13.0.6.
-   Update to Roundcube 1.3.7.
-   Update to Z-Push 2.4.4.
-   Backup dates listed in the control panel now use an internationalized format.

## v0.28 (July 30, 2018)

System:

-   We now use EFF’s `certbot` to provision TLS certificates (from Let’s Encrypt) instead of our home-grown ACME library.

Contacts/Calendar:

-   Fix for Mac OS X autoconfig of the calendar.

Setup:

-   Installing Z-Push broke because of what looks like a change or problem in their git server HTTPS certificate. That’s fixed.

## v0.27 (June 14, 2018)

Mail:

-   A report of box activity, including sent/received mail totals and logins by user, is now emailed to the box’s administrator user each week.
-   Update Roundcube to version 1.3.6 and Z-Push to version 2.3.9.

Control Panel:

-   The undocumented feature for proxying web requests to another server now sets X-Forwarded-For.

## v0.26c (February 13, 2018)

Setup:

-   Upgrades from v0.21c (February 1, 2017) or earlier were broken because the intermediate versions of ownCloud used in setup were no longer available from ownCloud.
-   Some download errors had no output --- there is more output on error now.

Control Panel:

-   The background service for the control panel was not restarting on updates, leaving the old version running. This was broken in v0.26 and is now fixed.
-   Installing your own TLS/SSL certificate had been broken since v0.24 because the new version of openssl became stricter about CSR generation parameters.
-   Fixed password length help text.

Contacts/Calendar:

-   Upgraded Nextcloud from 12.0.3 to 12.0.5.

## v0.26b (January 25, 2018)

-   Fix new installations which broke at the step of asking for the user’s desired email address, which was broken by v0.26’s changes related to the control panel.
-   Fix the provisioning of TLS certificates by pinning a Python package we rely on (acme) to an earlier version because our code isn’t yet compatible with its current version.
-   Reduce munin’s log_level from debug to warning to prevent massive log files.

## v0.26 (January 18, 2018)

Security:

-   HTTPS, IMAP, and POP’s TLS settings have been updated to Mozilla’s intermediate cipher list recommendation. Some extremely old devices that use less secure TLS ciphers may no longer be able to connect to IMAP/POP.
-   Updated web HSTS header to use longer six month duration.

Mail:

-   Adding attachments in Roundcube broke after the last update for some users after rebooting because a temporary directory was deleted on reboot. The temporary directory is now moved from /tmp to /var so that it is persistent.
-   `X-Spam-Score` header is added to incoming mail.

Control panel:

-   RSASHA256 is now used for DNSSEC for .lv domains.
-   Some documentation/links improvements.

Installer:

-   We now run `apt-get autoremove` at the start of setup to clear out old packages, especially old kernels that take up a lot of space. On the first run, this step may take a long time.
-   We now fetch Z-Push from its tagged git repository, fixing an installation problem.
-   Some old PHP5 packages are removed from setup, fixing an installation bug where Apache would get installed.
-   Python 3 packages for the control panel are now installed using a virtualenv to prevent installation errors due to conflicts in the cryptography/openssl packages between OS-installed packages and pip-installed packages.

## v0.25 (November 15, 2017)

This update is a security update addressing [CVE-2017-16651, a vulnerability in Roundcube webmail that allows logged-in users to access files on the local filesystem](https://roundcube.net/news/2017/11/08/security-updates-1.3.3-1.2.7-and-1.1.10).

Mail:

-   Update to Roundcube 1.3.3.

Control Panel:

-   Allow custom DNS records to be set for DNS wildcard subdomains (i.e. `*`).

## v0.24 (October 3, 2017)

System:

-   Install PHP7 via a PPA. Switch to the on-demand process manager.

Mail:

-   Updated to [Roundcube 1.3.1](https://roundcube.net/news/2017/06/26/roundcube-webmail-1.3.0-released), but unfortunately dropping the Vacation plugin because it has not been supported by its author and is not compatible with Roundcube 1.3, and updated the persistent login plugin.
-   Updated to [Z-Push 2.3.8](http://download.z-push.org/final/2.3/z-push-2.3.8.txt).
-   Dovecot now uses stronger 2048 bit DH params for better forward secrecy.

Nextcloud:

-   Nextcloud updated to 12.0.3, using PHP7.

Control Panel:

-   Nameserver (NS) records can now be set on custom domains.
-   Fix an erroneous status check error due to IPv6 address formatting.
-   Aliases for administrative addresses can now be set to send mail to +tag administrative addresses.

## v0.23a (May 31, 2017)

Corrects a problem in the new way third-party assets are downloaded during setup for the control panel, since v0.23.

## v0.23 (May 30, 2017)

Mail:

-   The default theme for Roundcube was changed to the nicer Larry theme.
-   Exchange/ActiveSync support has been replaced with z-push 2.3.6 from z-push.org (rather than z-push-contrib).

ownCloud (now Nextcloud):

-   ownCloud is replaced with Nextcloud 10.0.5.
-   Fixed an error in Owncloud/Nextcloud setup not updating domain when changing hostname.

Control Panel/Management:

-   Fix an error in the control panel showing rsync backup status.
-   Fix an error in the control panel related to IPv6 addresses.
-   TLS certificates for internationalized domain names can now be provisioned from Let’s Encrypt automatically.
-   Third-party assets used in the control panel (jQuery/Bootstrap) are now downloaded during setup and served from the box rather than from a CDN.

DNS:

-   Add support for custom CAA records.

## v0.22 (April 2, 2017)

Mail:

-   The CardDAV plugin has been added to Roundcube so that your ownCloud contacts are available in webmail.
-   Upgraded to Roundcube 1.2.4 and updated the persistent login plugin.
-   Allow larger messages to be checked by SpamAssassin.
-   Dovecot’s vsz memory limit has been increased proportional to system memory.
-   Newly set user passwords must be at least eight characters.

ownCloud:

-   Upgraded to ownCloud 9.1.4.

Control Panel/Management:

-   The status checks page crashed when the mailinabox.email website was down - that’s fixed.
-   Made nightly re-provisioning of TLS certificates less noisy.
-   Fixed bugs in rsync backup method and in the list of recent backups.
-   Fixed incorrect status checks errors about IPv6 addresses.
-   Fixed incorrect status checks errors for secondary nameservers if round-robin custom A records are set.
-   The management mail_log.py tool has been rewritten.

DNS:

-   Added support for DSA, ED25519, and custom SSHFP records.

System:

-   The SSH fail2ban jail was not activated.

Installation:

-   At the end of installation, the SHA256 -- rather than SHA1 -- hash of the system’s TLS certificate is shown.

## v0.21c (February 1, 2017)

Installations and upgrades started failing about 10 days ago with the error “ImportError: No module named ‘packaging’” after an upstream package (Python’s setuptools) was updated by its maintainers. The updated package conflicted with Ubuntu 14.04’s version of another package (Python’s pip). This update upgrades both packages to remove the conflict.

If you already encountered the error during installation or upgrade of Mail-in-a-Box, this update may not correct the problem on your existing system. See https://discourse.mailinabox.email/t/v0-21c-release-fixes-python-package-installation-issue/1881 for help if the problem persists after upgrading to this version of Mail-in-a-Box.

## v0.21b (December 4, 2016)

This update corrects a first-time installation issue introduced in v0.21 caused by the new Exchange/ActiveSync feature.

## v0.21 (November 30, 2016)

This version updates ownCloud, which may include security fixes, and makes some other smaller improvements.

Mail:

-   Header privacy filters were improperly running on the contents of forwarded email --- that’s fixed.
-   We have another go at fixing a long-standing issue with training the spam filter (because of a file permissions issue).
-   Exchange/ActiveSync will now use your display name set in Roundcube in the From: line of outgoing email.

ownCloud:

-   Updated ownCloud to version 9.1.1.

Control panel:

-   Backups can now be made using rsync-over-ssh!
-   Status checks failed if the system doesn’t support iptables or doesn’t have ufw installed.
-   Added support for SSHFP records when sshd listens on non-standard ports.
-   Recommendations for TLS certificate providers were removed now that everyone mostly uses Let’s Encrypt.

System:

-   Ubuntu’s “Upgrade to 16.04” notice is suppressed since you should not do that.
-   Lowered memory requirements to 512MB, display a warning if system memory is below 768MB.

## v0.20 (September 23, 2016)

ownCloud:

-   Updated to ownCloud to 8.2.7.

Control Panel:

-   Fixed a crash that occurs when there are IPv6 DNS records due to a bug in dnspython 1.14.0.
-   Improved the wonky low disk space check.

## v0.19b (August 20, 2016)

This update corrects a security issue introduced in v0.18.

-   A remote code execution vulnerability is corrected in how the munin system monitoring graphs are generated for the control panel. The vulnerability involves an administrative user visiting a carefully crafted URL.

## v0.19a (August 18, 2016)

This update corrects a security issue in v0.19.

-   fail2ban won’t start if Roundcube had not yet been used - new installations probably do not have fail2ban running.

## v0.19 (August 13, 2016)

Mail:

-   Roundcube is updated to version 1.2.1.
-   SSLv3 and RC4 are now no longer supported in incoming and outgoing mail (SMTP port 25).

Control panel:

-   The users and aliases APIs are now documented on their control panel pages.
-   The HSTS header was missing.
-   New status checks were added for the ufw firewall.

DNS:

-   Add SRV records for CardDAV/CalDAV to facilitate autoconfiguration (e.g. in DavDroid, whose latest version didn’t seem to work to configure with entering just a hostname).

System:

-   fail2ban jails added for SMTP submission, Roundcube, ownCloud, the control panel, and munin.
-   Mail-in-a-Box can now be installed on the i686 architecture.

## v0.18c (June 2, 2016)

-   Domain aliases (and misconfigured aliases/catch-alls with non-existent local targets) would accept mail and deliver it to new mailbox folders on disk even if the target address didn’t correspond with an existing mail user, instead of rejecting the mail. This issue was introduced in v0.18.
-   The Munin Monitoring link in the control panel now opens a new window.
-   Added an undocumented before-backup script.

## v0.18b (May 16, 2016)

-   Fixed a Roundcube user accounts issue introduced in v0.18.

## v0.18 (May 15, 2016)

ownCloud:

-   Updated to ownCloud to 8.2.3

Mail:

-   Roundcube is updated to version 1.1.5 and the Roundcube login screen now says ”[hostname] Webmail” instead of “Mail-in-a-Box/Roundcube webmail”.
-   Fixed a long-standing issue with training the spam filter not working (because of a file permissions issue).

Control panel:

-   Munin system monitoring graphs are now zoomable.
-   When a reboot is required (due to Ubuntu security updates automatically installed), a Reboot Box button now appears on the System Status Checks page of the control panel.
-   It is now possible to add SRV and secondary MX records in the Custom DNS page.
-   Other minor fixes.

System:

-   The fail2ban recidive jail, which blocks long-duration brute force attacks, now no longer sends the administrator emails (which were not helpful).

Setup:

-   The system hostname is now set during setup.
-   A swap file is now created if system memory is less than 2GB, 5GB of free disk space is available, and if no swap file yet exists.
-   We now install Roundcube from the official GitHub repository instead of our own mirror, which we had previously created to solve problems with SourceForge.
-   DKIM was incorrectly set up on machines where “localhost” was defined as something other than “127.0.0.1”.

## v0.17c (April 1, 2016)

This update addresses some minor security concerns and some installation issues.

ownCoud:

-   Block web access to the configuration parameters (config.php). There is no immediate impact (see [#776](https://github.com/mail-in-a-box/mailinabox/pull/776)), although advanced users may want to take note.

Mail:

-   Roundcube html5_notifier plugin updated from version 0.6 to 0.6.2 to fix Roundcube getting stuck for some people.

Control panel:

-   Prevent click-jacking of the management interface by adding HTTP headers.
-   Failed login no longer reveals whether an account exists on the system.

Setup:

-   Setup dialogs did not appear correctly when connecting to SSH using Putty on Windows.
-   We now install Roundcube from our own mirror because Sourceforge’s downloads experience frequent intermittant unavailability.

## v0.17b (March 1, 2016)

ownCloud moved their source code to a new location, breaking our installation script.

## v0.17 (February 25, 2016)

Mail:

-   Roundcube updated to version 1.1.4.
-   When there’s a problem delivering an outgoing message, a new ‘warning’ bounce will come after 3 hours and the box will stop trying after 2 days (instead of 5).
-   On multi-homed machines, Postfix now binds to the right network interface when sending outbound mail so that SPF checks on the receiving end will pass.
-   Mail sent from addresses on subdomains of other domains hosted by this box would not be DKIM-signed and so would fail DMARC checks by recipients, since version v0.15.

Control panel:

-   TLS certificate provisioning would crash if DNS propagation was in progress and a challenge failed; might have shown the wrong error when provisioning fails.
-   Backup times were displayed with the wrong time zone.
-   Thresholds for displaying messages when the system is running low on memory have been reduced from 30% to 20% for a warning and from 15% to 10% for an error.
-   Other minor fixes.

System:

-   Backups to some AWS S3 regions broke in version 0.15 because we reverted the version of boto. That’s now fixed.
-   On low-usage systems, don’t hold backups for quite so long by taking a full backup more often.
-   Nightly status checks might fail on systems not configured with a default Unicode locale.
-   If domains need a TLS certificate and the user hasn’t installed one yet using Let’s Encrypt, the administrator would get a nightly email with weird interactive text asking them to agree to Let’s Encrypt’s ToS. Now just say that the provisioning can’t be done automatically.
-   Reduce the number of background processes used by the management daemon to lower memory consumption.

Setup:

-   The first screen now warns users not to install on a machine used for other things.

## v0.16 (January 30, 2016)

This update primarily adds automatic SSL (now “TLS”) certificate provisioning from Let’s Encrypt (https://letsencrypt.org/).

Control Panel:

-   The SSL certificates (now referred to as “TLS ccertificates”) page now supports provisioning free certificates from Let’s Encrypt.
-   Report free memory usage.
-   Fix a crash when the git directory is not checked out to a tag.
-   When IPv6 is enabled, check that all domains (besides the system hostname) resolve over IPv6.
-   When a domain doesn’t resolve to the box, don’t bother checking if the TLS certificate is valid.
-   Remove rounded border on the menu bar.

Other:

-   The Sieve port is now open so tools like the Thunderbird Sieve extension can be used to edit mail filters.
-   .be domains now offer DNSSEC options supported by the TLD
-   The daily backup will now email the administrator if there is a problem.
-   Expiring TLS certificates are now automatically renewed via Let’s Encrypt.
-   File ownership for installed Roundcube files is fixed.
-   Typos fixed.

## v0.15a (January 9, 2016)

Mail:

-   Sending mail through Exchange/ActiveSync (Z-Push) had been broken since v0.14 in some setups. This is now fixed.

## v0.15 (January 1, 2016)

Mail:

-   Updated Roundcube to version 1.1.3.
-   Auto-create aliases for abuse@, as required by RFC2142.
-   The DANE TLSA record is changed to use the certificate subject public key rather than the whole certificate, which means the record remains valid after certificate changes (so long as the private key remains the same, which it does for us).

Control panel:

-   When IPv6 is enabled, check that system services are accessible over IPv6 too, that the box’s hostname resolves over IPv6, and that reverse DNS is setup correctly for IPv6.
-   Explanatory text for setting up secondary nameserver is added/fixed.
-   DNS checks now have a timeout in case a DNS server is not responding, so the checks don’t stall indefinitely.
-   Better messages if external DNS is used and, weirdly, custom secondary nameservers are set.
-   Add POP to the mail client settings documentation.
-   The box’s IP address is added to the fail2ban whitelist so that the status checks don’t trigger the machine banning itself, which results in the status checks showing services down even though they are running.
-   For SSL certificates, rather than asking you what country you are in during setup, ask at the time a CSR is generated. The default system self-signed certificate now omits a country in the subject (it was never needed). The CSR_COUNTRY Mail-in-a-Box setting is dropped entirely.

System:

-   Nightly backups and system status checks are now moved to 3am in the system’s timezone.
-   fail2ban’s recidive jail is now active, which guards against persistent brute force login attacks over long periods of time.
-   Setup (first run only) now asks for your timezone to set the system time.
-   The Exchange/ActiveSync server is now taken offline during nightly backups (along with SMTP and IMAP).
-   The machine’s random number generator (/dev/urandom) is now seeded with Ubuntu Pollinate and a blocking read on /dev/random.
-   DNSSEC key generation during install now uses /dev/urandom (instead of /dev/random), which is faster.
-   The $STORAGE_ROOT/ssl directory is flattened by a migration script and the system SSL certificate path is now a symlink to the actual certificate.
-   If ownCloud sends out email, it will use the box’s administrative address now (admin@yourboxname).
-   Z-Push (Exchange/ActiveSync) logs now exclude warnings and are now rotated to save disk space.
-   Fix pip command that might have not installed all necessary Python packages.
-   The control panel and backup would not work on Google Compute Engine because GCE installs a conflicting boto package.
-   Added a new command `management/backup.py --restore` to restore files from a backup to a target directory (command line arguments are passed to `duplicity restore`).

## v0.14 (November 4, 2015)

Mail:

-   Spamassassin’s network-based tests (Pyzor, others) and DKIM tests are now enabled. (Pyzor had always been installed but was not active due to a misconfiguration.)
-   Moving spam out of the Spam folder and into Trash would incorrectly train Spamassassin that those messages were not spam.
-   Automatically create the Sent and Archive folders for new users.
-   The HTML5_Notifier plugin for Roundcube is now included, which when turned on in Roundcube settings provides desktop notifications for new mail.
-   The Exchange/ActiveSync backend Z-Push has been updated to fix a problem with CC’d emails not being sent to the CC recipients.

Calender/Contacts:

-   CalDAV/CardDAV and Exchange/ActiveSync for calendar/contacts wasn’t working in some network configurations.

Web:

-   When a new domain is added to the box, rather than applying a new self-signed certificate for that domain, the SSL certificate for the box’s primary hostname will be used instead.
-   If a custom DNS record is set on a domain or ‘www’+domain, web would not be served for that domain. If the custom DNS record is just the box’s IP address, that’s a configuration mistake, but allow it and let web continue to be served.
-   Accommodate really long domain names by increasing an nginx setting.

Control panel:

-   Added an option to check for new Mail-in-a-Box versions within status checks. It is off by default so that boxes don’t “phone home” without permission.
-   Added a random password generator on the users page to simplify creating new accounts.
-   When S3 backup credentials are set, the credentials are now no longer ever sent back from the box to the client, for better security.
-   Fixed the jumpiness when a modal is displayed.
-   Focus is put into the login form fields when the login form is displayed.
-   Status checks now include a warning if a custom DNS record has been set on a domain that would normally serve web and as a result that domain no longer is serving web.
-   Status checks now check that secondary nameservers, if specified, are actually serving the domains.
-   Some errors in the control panel when there is invalid data in the database or an improperly named archived user account have been suppressed.
-   Added subresource integrity attributes to all remotely-sourced resources (i.e. via CDNs) to guard against CDNs being used as an attack vector.

System:

-   Tweaks to fail2ban settings.
-   Fixed a spurrious warning while installing munin.

## v0.13b (August 30, 2015)

Another ownCloud 8.1.1 issue was found. New installations left ownCloud improperly setup (“You are accessing the server from an untrusted domain.”). Upgrading to this version will fix that.

## v0.13a (August 23, 2015)

Note: v0.13 (no ‘a’, August 19, 2015) was pulled immediately due to an ownCloud bug that prevented upgrades. v0.13a works around that problem.

Mail:

-   Outbound mail headers (the Recieved: header) are tweaked to possibly improve deliverability.
-   Some MIME messages would hang Roundcube due to a missing package.
-   The users permitted to send as an alias can now be different from where an alias forwards to.

DNS:

-   The secondary nameservers option in the control panel now accepts more than one nameserver and a special xfr:IP format to specify zone-transfer-only IP addresses.
-   A TLSA record is added for HTTPS for DNSSEC-aware clients that support it.

System:

-   Backups can now be turned off, or stored in Amazon S3, through new control panel options.
-   Munin was not working on machines confused about their hostname and had lots of errors related to PANGO, NTP peers and network interfaces that were not up.
-   ownCloud updated to version 8.1.1 (with upgrade work-around), its memcached caching enabled.
-   When upgrading, network checks like blocked port 25 are now skipped.
-   Tweaks to the intrusion detection rules for IMAP.
-   Mail-in-a-Box’s setup is a lot quieter, hiding lots of irrelevant messages.

Control panel:

-   SSL certificate checks were failing on OVH/OpenVZ servers due to missing /dev/stdin.
-   Improve the sort order of the domains in the status checks.
-   Some links in the control panel were only working in Chrome.

## v0.12c (July 19, 2015)

v0.12c was posted to work around the current Sourceforge.net outage: pyzor’s remote server is now hard-coded rather than accessing a file hosted on Sourceforge, and roundcube is now downloaded from a Mail-in-a-Box mirror rather than from Sourceforge.

## v0.12b (July 4, 2015)

This version corrects a minor regression in v0.12 related to creating aliases targetting multiple addresses.

## v0.12 (July 3, 2015)

This is a minor update to v0.11, which was a major update. Please read v0.11’s advisories.

-   The administrator@ alias was incorrectly created starting with v0.11. If your first install was v0.11, check that the administrator@ alias forwards mail to you.
-   Intrusion detection rules (fail2ban) are relaxed (i.e. less is blocked).
-   SSL certificates could not be installed for the new automatic ‘www.’ redirect domains.
-   PHP’s default character encoding is changed from no default to UTF8. The effect of this change is unclear but should prevent possible future text conversion issues.
-   User-installed SSL private keys in the BEGIN PRIVATE KEY format were not accepted.
-   SSL certificates with SAN domains with IDNA encoding were broken in v0.11.
-   Some IDNA functionality was using IDNA 2003 rather than IDNA 2008.

## v0.11b (June 29, 2015)

v0.11b was posted shortly after the initial posting of v0.11 to correct a missing dependency for the new PPA.

## v0.11 (June 29, 2015)

Advisories:

-   Users can no longer spoof arbitrary email addresses in outbound mail. When sending mail, the email address configured in your mail client must match the SMTP login username being used, or the email address must be an alias with the SMTP login username listed as one of the alias’s targets.
-   This update replaces your DKIM signing key with a stronger key. Because of DNS caching/propagation, mail sent within a few hours after this update could be marked as spam by recipients. If you use External DNS, you will need to update your DNS records.
-   The box will now install software from a new Mail-in-a-Box PPA on Launchpad.net, where we are distributing two of our own packages: a patched postgrey and dovecot-lucene.

Mail:

-   Greylisting will now let some reputable senders pass through immediately.
-   Searching mail (via IMAP) will now be much faster using the dovecot lucene full text search plugin.
-   Users can no longer spoof arbitrary email addresses in outbound mail (see above).
-   Fix for deleting admin@ and postmaster@ addresses.
-   Roundcube is updated to version 1.1.2, plugins updated.
-   Exchange/ActiveSync autoconfiguration was not working on all devices (e.g. iPhone) because of a case-sensitive URL.
-   The DKIM signing key has been increased to 2048 bits, from 1024, replacing the existing key.

Web:

-   ’www’ subdomains now automatically redirect to their parent domain (but you’ll need to install an SSL certificate).
-   OCSP no longer uses Google Public DNS.
-   The installed PHP version is no longer exposed through HTTP response headers, for better security.

DNS:

-   Default IPv6 AAAA records were missing since version 0.09.

Control panel:

-   Resetting a user’s password now forces them to log in again everywhere.
-   Status checks were not working if an ssh server was not installed.
-   SSL certificate validation now uses the Python cryptography module in some places where openssl was used.
-   There is a new tab to show the installed version of Mail-in-a-Box and to fetch the latest released version.

System:

-   The munin system monitoring tool is now installed and accessible at /admin/munin.
-   ownCloud updated to version 8.0.4. The ownCloud installation step now is reslient to download problems. The ownCloud configuration file is now stored in STORAGE_ROOT to fix loss of data when moving STORAGE_ROOT to a new machine.
-   The setup scripts now run `apt-get update` prior to installing anything to ensure the apt database is in sync with the packages actually available.

## v0.10 (June 1, 2015)

-   SMTP Submission (port 587) began offering the insecure SSLv3 protocol due to a misconfiguration in the previous version.
-   Roundcube now allows persistent logins using Roundcube-Persistent-Login-Plugin.
-   ownCloud is updated to version 8.0.3.
-   SPF records for non-mail domains were tightened.
-   The minimum greylisting delay has been reduced from 5 minutes to 3 minutes.
-   Users and aliases weren’t working if they were entered with any uppercase letters. Now only lowercase is allowed.
-   After installing an SSL certificate from the control panel, the page wasn’t being refreshed.
-   Backups broke if the box’s hostname was changed after installation.
-   Dotfiles (i.e. .svn) stored in ownCloud Files were not accessible from ownCloud’s mobile/desktop clients.
-   Fix broken install on OVH VPS’s.

## v0.09 (May 8, 2015)

Mail:

-   Spam checking is now performed on messages larger than the previous limit of 64KB.
-   POP3S is now enabled (port 995).
-   Roundcube is updated to version 1.1.1.
-   Minor security improvements (more mail headers with user agent info are anonymized; crypto settings were tightened).

ownCloud:

-   Downloading files you uploaded to ownCloud broke because of a change in ownCloud 8.

DNS:

-   Internationalized Domain Names (IDNs) should now work in email. If you had custom DNS or custom web settings for internationalized domains, check that they are still working.
-   It is now possible to set multiple TXT and other types of records on the same domain in the control panel.
-   The custom DNS API was completely rewritten to support setting multiple records of the same type on a domain. Any existing client code using the DNS API will have to be rewritten. (Existing code will just get 404s back.)
-   On some systems the `nsd` service failed to start if network inferfaces were not ready.

System / Control Panel:

-   In order to guard against misconfiguration that can lead to domain control validation hijacking, email addresses that begin with admin, administrator, postmaster, hostmaster, and webmaster can no longer be used for (new) mail user accounts, and aliases for these addresses may direct mail only to the box’s administrator(s).
-   Backups now use duplicity’s built-in gpg symmetric AES256 encryption rather than my home-brewed encryption. Old backups will be incorporated inside the first backup after this update but then deleted from disk (i.e. your backups from the previous few days will be backed up).
-   There was a race condition between backups and the new nightly status checks.
-   The control panel would sometimes lock up with an unnecessary loading indicator.
-   You can no longer delete your own account from the control panel.

Setup:

-   All Mail-in-a-Box release tags are now signed on github, instructions for verifying the signature are added to the README, and the integrity of some packages downloaded during setup is now verified against a SHA1 hash stored in the tag itself.
-   Bugs in first user account creation were fixed.

## v0.08 (April 1, 2015)

Mail:

-   The Roundcube vacation_sieve plugin by @arodier is now installed to make it easier to set vacation auto-reply messages from within Roundcube.
-   Authentication-Results headers for DMARC, added in v0.07, were mistakenly added for outbound mail --- that’s now removed.
-   The Trash folder is now created automatically for new mail accounts, addressing a Roundcube error.

DNS:

-   Custom DNS TXT records were not always working and they can now override the default SPF, DKIM, and DMARC records.

System:

-   ownCloud updated to version 8.0.2.
-   Brute-force SSH and IMAP login attempts are now prevented by properly configuring fail2ban.
-   Status checks are run each night and any changes from night to night are emailed to the box administrator (the first user account).

Control panel:

-   The new check that system services are running mistakenly checked that the Dovecot Managesieve service is publicly accessible. Although the service binds to the public network interface we don’t open the port in ufw. On some machines it seems that ufw blocks the connection from the status checks (which seems correct) and on some machines (mine) it doesn’t, which is why I didn’t notice the problem.
-   The current backup chain will now try to predict how many days until it is deleted (always at least 3 days after the next full backup).
-   The list of aliases that forward to a user are removed from the Mail Users page because when there are many alises it is slow and times-out.
-   Some status check errors are turned into warnings, especially those that might not apply if External DNS is used.

## v0.07 (February 28, 2015)

Mail:

-   If the box manages mail for a domain and a subdomain of that domain, outbound mail from the subdomain was not DKIM-signed and would therefore fail DMARC tests on the receiving end, possibly result in the mail heading into spam folders.
-   Auto-configuration for Mozilla Thunderbird, Evolution, KMail, and Kontact is now available.
-   Domains that only have a catch-all alias or domain alias no longer automatically create/require admin@ and postmaster@ addresses since they’ll forward anyway.
-   Roundcube is updated to version 1.1.0.
-   Authentication-Results headers for DMARC are now added to incoming mail.

DNS:

-   If a custom CNAME record is set on a ‘www’ subdomain, the default A/AAAA records were preventing the CNAME from working.
-   If a custom DNS A record overrides one provided by the box, the a corresponding default IPv6 record by the box is removed since it will probably be incorrect.
-   Internationalized domain names (IDNs) are now supported for DNS and web, but email is not yet tested.

Web:

-   Static websites now deny access to certain dot (.) files and directories which typically have sensitive info: .ht*, .svn*, .git*, .hg*, .bzr\*.
-   The nginx server no longer reports its version and OS for better privacy.
-   The HTTP->HTTPS redirect is now more efficient.
-   When serving a ‘www.’ domain, reuse the SSL certificate for the parent domain if it covers the ‘www’ subdomain too
-   If a custom DNS CNAME record is set on a domain, don’t offer to put a website on that domain. (Same logic already applies to custom A/AAAA records.)

Control panel:

-   Status checks now check that system services are actually running by pinging each port that should have something running on it.
-   The status checks are now parallelized so they may be a little faster.
-   The status check for MX records now allow any priority, in case an unusual setup is required.
-   The interface for setting website domain-specific directories is simplified.
-   The mail guide now says that to use Outlook, Outlook 2007 or later on Windows 7 and later is required.
-   External DNS settings now skip the special “\_secondary_nameserver” key which is used for storing secondary NS information.

Setup:

-   Install cron if it isn’t already installed.
-   Fix a units problem in the minimum memory check.
-   If you override the STORAGE_ROOT, your setting will now persist if you re-run setup.
-   Hangs due to apt wanting the user to resolve a conflict should now be fixed (apt will just clobber the problematic file now).

## v0.06 (January 4, 2015)

Mail:

-   Set better default system limits to accommodate boxes handling mail for 20+ users.

Contacts/calendar:

-   Update to ownCloud to 7.0.4.
-   Contacts syncing via ActiveSync wasn’t working.

Control panel:

-   New control panel for setting custom DNS settings (without having to use the API).
-   Status checks showed a false positive for Spamhause blacklists and for secondary DNS in some cases.
-   Status checks would fail to load if openssh-sever was not pre-installed, but openssh-server is not required.
-   The local DNS cache is cleared before running the status checks using ‘rncd’ now rather than restarting ‘bind9’, which should be faster and wont interrupt other services.
-   Multi-domain and wildcard certificate can now be installed through the control panel.
-   The DNS API now allows the setting of SRV records.

Misc:

-   IPv6 configuration error in postgrey, nginx.
-   Missing dependency on sudo.

## v0.05 (November 18, 2014)

Mail:

-   The maximum size of outbound mail sent via webmail and Exchange/ActiveSync has been increased to 128 MB, the same as when using SMTP.
-   Spam is no longer wrapped as an attachment inside a scary Spamassassin explanation. The original message is simply moved straight to the Spam folder unchanged.
-   There is a new iOS/Mac OS X Configuration Profile link in the control panel which makes it easier to configure IMAP/SMTP/CalDAV/CardDAV on iOS devices and Macs.
-   “Domain aliases” can now be configured in the control panel.
-   Updated to [Roundcube 1.0.3](http://trac.roundcube.net/wiki/Changelog).
-   IMAP/SMTP is now recommended even on iOS devices as Exchange/ActiveSync is terribly buggy.

Control panel:

-   Installing an SSL certificate for the primary hostname would cause problems until a restart (services needed to be restarted).
-   Installing SSL certificates would fail if /tmp was on a different filesystem.
-   Better error messages when installing a SSL certificate fails.
-   The local DNS cache is now cleared each time the system status checks are run.
-   Documented how to use +tag addressing.
-   Minor UI tweaks.

Other:

-   Updated to [ownCloud 7.0.3](http://owncloud.org/changelog/).
-   The ownCloud API is now exposed properly.
-   DNSSEC now works on `.guide` domains now too (RSASHA256).

## v0.04 (October 15, 2014)

Breaking changes:

-   On-disk backups are now retained for a minimum of 3 days instead of 14. Beyond that the user is responsible for making off-site copies.
-   IMAP no longer supports the legacy SSLv3 protocol. SSLv3 is now known to be insecure. I don’t believe any modern devices will be affected by this. HTTPS and SMTP submission already had SSLv3 disabled.

Control panel:

-   The control panel has a new page for installing SSL certificates.
-   The control panel has a new page for hosting static websites.
-   The control panel now shows mailbox sizes on disk.
-   It is now possible to create catch-all aliases from the control panel.
-   Many usability improvements in the control panel.

DNS:

-   Custom DNS A/AAAA records on subdomains were ignored.
-   It is now possible to set up a secondary DNS server.
-   DNS zones were updating even when nothing changed.
-   Strict SPF and DMARC settings are now set on all subdomains not used for mail.

Security:

-   DNSSEC is now supported for the .email TLD which required a different key algorithm.
-   Nginx and Postfix now use 2048 bits of DH parameters instead of 1024.

Other:

-   Spam filter learning by dragging mail in and out of the Spam folder should hopefully be working now.
-   Some things were broken if the machine had an IPv6 address.
-   Other things were broken if the machine was on a non-utf8 locale.
-   No longer implementing webfinger.
-   Removes apache before installing nginx, in case it has been installed by distro.

## v0.03 (September 24, 2014)

-   Update existing installs of Roundcube.
-   Disabled catch-alls pending figuring out how to get users to take precedence.
-   Z-Push was not working because in v0.02 we had accidentally moved to a different version.
-   Z-Push is now locked to a specific commit so it doesn’t change on us accidentally.
-   The start script is now symlinked to /usr/local/bin/mailinabox.

## v0.02 (September 21, 2014)

-   Open the firewall to an alternative SSH port if set.
-   Fixed missing dependencies.
-   Set Z-Push to use sync command with ownCloud.
-   Support more concurrent connections for z-push.
-   In the status checks, handle wildcard certificates.
-   Show the status of backups in the control panel.
-   The control panel can now update a user’s password.
-   Some usability improvements in the control panel.
-   Warn if a SSL cert is expiring in 30 days.
-   Use SHA2 to generate CSRs.
-   Better logic for determining when to take a full backup.
-   Reduce DNS TTL, not that it seems to really matter.
-   Add SSHFP DNS records.
-   Add an API for setting custom DNS records
-   Update to ownCloud 7.0.2.
-   Some things were broken if the machine had an IPv6 address.
-   Use a dialogs library to ask users questions during setup.
-   Other fixes.

## v0.01 (August 19, 2014)

First versioned release after a year of unversioned development.
