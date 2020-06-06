[![Build Status](https://travis-ci.com/downtownallday/mailinabox-ldap.svg?branch=master)](https://travis-ci.com/downtownallday/mailinabox-ldap)

Mail-in-a-Box LDAP
===================
This is a version of [Mail-in-a-Box](https://mailinabox.email) with LDAP used as the user account database instead of sqlite.

All features are supported - you won't find many visible differences. It's only an under-the-hood change.

However it will allow a remote Nextcloud installation to authenticate users against Mail-in-a-Box using [Nextcloud's official LDAP support](https://nextcloud.com/usermanagement/). A single user account database shared with Nextcloud was originally the goal of the project which would simplify deploying a private mail and cloud service for a home or small business. But, there could be many other use cases as well. 

To add a new account to Nextcloud, you'd simply add a new email account with MiaB-LDAP's admin interface. Quotas and other account settings are made within Nextcloud.

How to connect a remote Nextcloud
---------------------------------

To fully integrate Mail-in-a-Box w/LDAP (MiaB-LDAP) with Nextcloud, changes must be made on both sides.

1. MiaB-LDAP
  * Remote LDAPS access: the default MiaB-LDAP installation doesn't allow any remote LDAP access, so for Nextcloud to access MiaB-LDAP, firewall rules must be loosened to the LDAPS port (636). This is a one-time change.  Run something like this as root on MiaB-LDAP, where $ip is the ip-address of your Nextcloud server:  `ufw allow proto tcp from $ip to any port ldaps`
  * Roundcube and Z-Push (ActiveSync) changes: modify the MiaB-LDAP configuration to use the remote Nextcloud for contacts and calendar. A script to do this automatically will be available soon.
2. Remote Nextcloud
  * Use MiaB-LDAP for user acccounts: on Nextcloud, enable user-ldap (in Apps, enable "LDAP user and group backend". Then in Settings click on "LDAP / AD integration". There are quite a few settings to make in there and more information on this will be forthcoming, including a script that will use the user-ldap API to configure the LDAP parameters in Nextcloud for you.

Details
-------

Once installed, you will find all LDAP service account credentials in `/home/user-data/ldap/miab_ldap.conf`, such as those for Nextcloud. Service accounts have limited rights to make changes and should be preferred over the use of the LDAP admin account.

See `conf/postfix.schema` for more details on the LDAP schema.

LDAP server access logs are stored in `/var/log/ldap/slapd.log` and rotated daily.

To perform general command-line searches against your LDAP database, run `setup/ldap -search "\<query\>"` as root, where _query_ can be a distinguished name to show all attributes of that dn, or an LDAP search enclosed in parenthesis. Some examples:
  * `setup/ldap.sh -search "(mail=alice@mydomain.com)"` (show alice)
  * `setup/ldap.sh -search "(|(mail=alice.*)(mail=bruce.*))"` (show all alices and bruces)
  * `setup/ldap.sh -search "(objectClass=mailuser)"` (show all users)
  * etc.

This is a convenient way to run ldapsearch having all the correct command line arguments.

Caution: do not make direct LDAP database changes, such as adding users or groups using ldapmodify or other LDAP database tool. Instead, use the MiaB admin interface or REST API. Adding or removing a user or group with the admin interface may trigger additional database and system changes by the management daemon, such as updating DNS zones for new email domains, updating group memberships, etc, that would not be performed with a direct change.


Migration
---------
Running any of the setup scripts to install MiaB-LDAP (`miab`, `setup/bootstrap.sh`, `setup/start.sh`, etc) will automatically migrate your current installation from sqlite to LDAP. Make a full MiaB backup before running!

