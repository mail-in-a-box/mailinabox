Mail-in-a-Box w/LDAP
===================
This is a version of [Mail-in-a-Box](https://mailinabox.email) with LDAP used as the user account database instead of sqlite.

All features are supported - you won't find many visible differences. It's really an under-the-hood change.

However it will allow a remote Nextcloud installation to authenticate users against Mail-in-a-Box using [Nextcloud's official LDAP support](https://nextcloud.com/usermanagement/). A single user account database shared with Nextcloud was originally the goal of the project which would simplify deploying a private mail and cloud service for a home or small business. But, there could be many other use cases as well. 

To add a new account to Nextcloud, you'd simply add a new email account with MiaB-LDAP's admin interface. Quotas and other account settings are made within Nextcloud.

How to connect a remote Nextcloud \[scripts coming soon\]
--------------------------------------------------

To fully integrate Mail-in-a-Box w/LDAP (MiaB-LDAP) with Nextcloud, changes must be made on both sides.

1. MiaB-LDAP
  * Remote LDAPS access: the default MiaB-LDAP installation doesn't allow any remote LDAP access, so for Nextcloud to access MiaB-LDAP, firewall rules must be loosened to the LDAPS port (636). This is a one-time change.  Run something like this as root on MiaB-LDAP, where $ip is the ip-address of your Nextcloud server:  `ufw allow proto tcp from $ip to any port ldaps`
  * Roundcube and Z-Push (ActiveSync) changes: modify the MiaB-LDAP configuration to use the remote Nextcloud for contacts and calendar. A script to do this automatically will be available soon.
2. Remote Nextcloud
  * Use MiaB-LDAP for user acccounts: a script to run on Nextcloud will be available soon that will enable the user-ldap app and utilize the user-ldap API to configure Nextcloud for you. This script will set all the required attributes and search parameters for use with MiaB-LDAP (there are quite a few), including use of the limited-rights LDAP service account generated just for Nextcloud by the MiaB-LDAP installation.

All the setup-generated LDAP service account credentials are stored in /home/user-data/ldap/miab_ldap.conf. See that file for the Nextcloud service account distinguised name and password.

Command-Line Searching
-----------------------------------
To perform command-line searches against your LDAP database, run setup/ldap -search "\<query\>", where _query_ could be a distinguished name to show all attributes of that dn, or an LDAP search enclosed in parenthesis. Some examples:
  * `setup/ldap.sh -search "(mail=alice@mydomain.com)"` (show alice)
  * `setup/ldap.sh -search "(|(mail=alice.*)(mail=bruce.*))"` (show all alices and bruces)
  * `setup/ldap.sh -search "(objectClass=mailuser)"` (show all users)
  * etc.

See the `conf/postfix.schema` file for more details on the LDAP schema.

Cautionary Note
-----------------------
The setup will migrate your current installation to LDAP. Have good backups before running.

Although I run this in production on my own servers, there are no guarantees that it will work for you.
