CHANGELOG for Debian Mail-in-a-Box (AiutoPcAmico)
=========

Versioning:
vXX.YY.ZZ
Where:

* XX is the upstream project version
* YY is the main release of the Debian Mail-in-a-Box project
* ZZ are minor releases of the Debian Mail-in-a-Box project (usually small fixes)

=========

Version 67.1.2 (December 29, 2023)
------------------------------

* Definitively removed systemd-resolved, because Debian doesen't install it anymore by default
* Fixed ```DNSStubListener=no```. Due to the lack of the previous package, this file did not exist and caused the installation to fail

Version 67.1.1 (December 29, 2023)
------------------------------

* Fixed greylist, because even though the user selected to disable it, it will be remained active
* Fixed installation, that would fail for problem with systemd-resolved package

Version 67.1.0 (December 29, 2023)
------------------------------

* Added ability to disable greylist
* Removed bootstrap.sh file, because we clone this repository each time
* Changed default Mail-in-a-Box homepage (now displays a warning when someone tries to reach our server on box.\[domainname\]/index.php page)
* Added some comments to identify AiutoPcAmico changes in the code
* More restrictive Fail2Ban configuration
* Updated ReadMe.md file and created CHANGELOG_AiutoPcAmico.md file

Version 67.0.0 (December 28, 2023)
------------------------------

* Implemented upstream changes (see CHANGELOG.md for details)

Version 65.1.1 (December 06, 2023)
------------------------------

* Modified SMTPd banner (now is more generic)

Version 65.1.0 (December 05, 2023)
------------------------------

* Removed all packages related only to Ubuntu
* Debian compatible packages installed
* Updated php from version 8.0 to version 8.2
* Disabled ownCloud, not compatible with php 8.2
* Added systemd-resolved installation, for DNS broken after installing Debian Mail-in-a-Box

Version 65.0.0 (December 05, 2023)
------------------------------

* Initial commit of this fork (Debian Mail-in-a-Box)
* Implemented upstream changes (see CHANGELOG.md for details)
