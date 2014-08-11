<?php
/***********************************************
* File      :   config.php
* Project   :   Z-Push
* Descr     :   IMAP backend configuration file
*
* Created   :   27.11.2012
*
* Copyright 2007 - 2013 Zarafa Deutschland GmbH
*
* This program is free software: you can redistribute it and/or modify
* it under the terms of the GNU Affero General Public License, version 3,
* as published by the Free Software Foundation with the following additional
* term according to sec. 7:
*
* According to sec. 7 of the GNU Affero General Public License, version 3,
* the terms of the AGPL are supplemented with the following terms:
*
* "Zarafa" is a registered trademark of Zarafa B.V.
* "Z-Push" is a registered trademark of Zarafa Deutschland GmbH
* The licensing of the Program under the AGPL does not imply a trademark license.
* Therefore any rights, title and interest in our trademarks remain entirely with us.
*
* However, if you propagate an unmodified version of the Program you are
* allowed to use the term "Z-Push" to indicate that you distribute the Program.
* Furthermore you may use our trademarks where it is necessary to indicate
* the intended purpose of a product or service provided you use it in accordance
* with honest practices in industrial or commercial matters.
* If you want to propagate modified versions of the Program under the name "Z-Push",
* you may only do so if you have a written permission by Zarafa Deutschland GmbH
* (to acquire a permission please contact Zarafa at trademark@zarafa.com).
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
* GNU Affero General Public License for more details.
*
* You should have received a copy of the GNU Affero General Public License
* along with this program.  If not, see <http://www.gnu.org/licenses/>.
*
* Consult LICENSE file for details
************************************************/

// ************************
//  BackendIMAP settings
// ************************

// Defines the server to which we want to connect
define('IMAP_SERVER', 'localhost');

// connecting to default port (143)
define('IMAP_PORT', 993);

// best cross-platform compatibility (see http://php.net/imap_open for options)
define('IMAP_OPTIONS', '/ssl/norsh/novalidate-cert');

// overwrite the "from" header with some value
// options:
//        ''              - do nothing, use the From header
//        'username'      - the username will be set (usefull if your login is equal to your emailaddress)
//        'domain'        - the value of the "domain" field is used
//        'sql'           - the username will be the result of a sql query. REMEMBER TO INSTALL PHP-PDO AND PHP-DATABASE
//        'ldap'          - the username will be the result of a ldap query. REMEMBER TO INSTALL PHP-LDAP!!
//        '@mydomain.com' - the username is used and the given string will be appended
define('IMAP_DEFAULTFROM', '');

// DSN: formatted PDO connection string
//    mysql:host=xxx;port=xxx;dbname=xxx
// USER: username to DB
// PASSWORD: password to DB
// OPTIONS: array with options needed
// QUERY: query to execute
// FIELDS: columns in the query
// FROM: string that will be the from, replacing the column names with the values
define('IMAP_FROM_SQL_DSN', '');
define('IMAP_FROM_SQL_USER', '');
define('IMAP_FROM_SQL_PASSWORD', '');
define('IMAP_FROM_SQL_OPTIONS', serialize(array(PDO::ATTR_PERSISTENT => true)));
define('IMAP_FROM_SQL_QUERY', "select first_name, last_name, mail_address from users where mail_address = '#username@#domain'");
define('IMAP_FROM_SQL_FIELDS', serialize(array('first_name', 'last_name', 'mail_address')));
define('IMAP_FROM_SQL_FROM', '#first_name #last_name <#mail_address>');

// SERVER: ldap server
// SERVER_PORT: ldap port
// USER: dn to use for connecting
// PASSWORD: password
// QUERY: query to execute
// FIELDS: columns in the query
// FROM: string that will be the from, replacing the field names with the values
define('IMAP_FROM_LDAP_SERVER', 'localhost');
define('IMAP_FROM_LDAP_SERVER_PORT', '389');
define('IMAP_FROM_LDAP_USER', 'cn=zpush,ou=servers,dc=zpush,dc=org');
define('IMAP_FROM_LDAP_PASSWORD', 'password');
define('IMAP_FROM_LDAP_BASE', 'dc=zpush,dc=org');
define('IMAP_FROM_LDAP_QUERY', '(mail=#username@#domain)');
define('IMAP_FROM_LDAP_FIELDS', serialize(array('givenname', 'sn', 'mail')));
define('IMAP_FROM_LDAP_FROM', '#givenname #sn <#mail>');


// copy outgoing mail to this folder. If not set z-push will try the default folders
define('IMAP_SENTFOLDER', '');

// forward messages inline (default true - inlined)
define('IMAP_INLINE_FORWARD', true);

// list of folders we want to exclude from sync. Names, or part of it, separated by |
// example: dovecot.sieve|archive|spam
define('IMAP_EXCLUDED_FOLDERS', '');


// Method used for sending mail
// mail => mail() php function
// sendmail => sendmail executable
// smtp => direct connection against SMTP
define('IMAP_SMTP_METHOD', 'smtp');

global $imap_smtp_params;
// SMTP Parameters
//      mail : no params
$imap_smtp_params = array();
//      sendmail
//$imap_smtp_params = array('sendmail_path' => '/usr/bin/sendmail', 'sendmail_args' => '-i');
//      smtp
//          "host"          - The server to connect. Default is localhost.
//          "port"          - The port to connect. Default is 25.
//          "auth"          - Whether or not to use SMTP authentication. Default is FALSE.
//          "username"      - The username to use for SMTP authentication. "imap_username" for using the same username as the imap server
//          "password"      - The password to use for SMTP authentication. "imap_password" for using the same password as the imap server
//          "localhost"     - The value to give when sending EHLO or HELO. Default is localhost
//          "timeout"       - The SMTP connection timeout. Default is NULL (no timeout).
//          "verp"          - Whether to use VERP or not. Default is FALSE.
//          "debug"         - Whether to enable SMTP debug mode or not. Default is FALSE.
//          "persist"       - Indicates whether or not the SMTP connection should persist over multiple calls to the send() method.
//          "pipelining"    - Indicates whether or not the SMTP commands pipelining should be used.
//$imap_smtp_params = array('host' => 'localhost', 'port' => 25, 'auth' => false);
// If you want to use SSL with port 25 or port 465 you must preppend "ssl://" before the hostname or IP of your SMTP server
// IMPORTANT: To use SSL you must use PHP 5.1 or later, install openssl libs and use ssl:// within the host variable
$imap_smtp_params = array('host' => 'ssl://localhost', 'port' => 587, 'auth' => true, 'username' => 'imap_username', 'password' => 'imap_password');


// If you are using IMAP_SMTP_METHOD = mail or sendmail and your sent messages are not correctly displayed you can change this to "\n".
//   BUT, it doesn't with RFC 2822 and will break if using smp method
define('MAIL_MIMEPART_CRLF', "\r\n");

?>