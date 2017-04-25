<?php
/***********************************************
* File      :   config.php
* Project   :   Z-Push
* Descr     :   IMAP backend configuration file
************************************************/

define('IMAP_SERVER', '127.0.0.1');
define('IMAP_PORT', 993);
define('IMAP_OPTIONS', '/ssl/norsh/novalidate-cert');
define('IMAP_DEFAULTFROM', 'sql');

define('SYSTEM_MIME_TYPES_MAPPING', '/etc/mime.types');
define('IMAP_AUTOSEEN_ON_DELETE', false);
define('IMAP_FOLDER_CONFIGURED', true);
define('IMAP_FOLDER_PREFIX', '');
define('IMAP_FOLDER_PREFIX_IN_INBOX', false);
// see our conf/dovecot-mailboxes.conf file for IMAP special flags settings
define('IMAP_FOLDER_INBOX', 'INBOX');
define('IMAP_FOLDER_SENT', 'SENT');
define('IMAP_FOLDER_DRAFT', 'DRAFTS');
define('IMAP_FOLDER_TRASH', 'TRASH');
define('IMAP_FOLDER_SPAM', 'SPAM');
define('IMAP_FOLDER_ARCHIVE', 'ARCHIVE');

define('IMAP_INLINE_FORWARD', true);
define('IMAP_EXCLUDED_FOLDERS', '');

define('IMAP_FROM_SQL_DSN', 'sqlite:STORAGE_ROOT/mail/roundcube/roundcube.sqlite');
define('IMAP_FROM_SQL_USER', '');
define('IMAP_FROM_SQL_PASSWORD', '');
define('IMAP_FROM_SQL_OPTIONS', serialize(array(PDO::ATTR_PERSISTENT => true)));
define('IMAP_FROM_SQL_QUERY', "SELECT name, email FROM identities i INNER JOIN users u ON i.user_id = u.user_id WHERE u.username = '#username' AND i.standard = 1 AND i.del = 0 AND i.name <> ''");
define('IMAP_FROM_SQL_FIELDS', serialize(array('name', 'email')));
define('IMAP_FROM_SQL_FROM', '#name <#email>');
define('IMAP_FROM_SQL_FULLNAME', '#name');

// not used
define('IMAP_FROM_LDAP_SERVER', '');
define('IMAP_FROM_LDAP_SERVER_PORT', '389');
define('IMAP_FROM_LDAP_USER', 'cn=zpush,ou=servers,dc=zpush,dc=org');
define('IMAP_FROM_LDAP_PASSWORD', 'password');
define('IMAP_FROM_LDAP_BASE', 'dc=zpush,dc=org');
define('IMAP_FROM_LDAP_QUERY', '(mail=#username@#domain)');
define('IMAP_FROM_LDAP_FIELDS', serialize(array('givenname', 'sn', 'mail')));
define('IMAP_FROM_LDAP_FROM', '#givenname #sn <#mail>');
define('IMAP_FROM_LDAP_FULLNAME', '#givenname #sn');

define('IMAP_SMTP_METHOD', 'sendmail');

global $imap_smtp_params;
$imap_smtp_params = array('host' => 'ssl://127.0.0.1', 'port' => 587, 'auth' => true, 'username' => 'imap_username', 'password' => 'imap_password');

define('MAIL_MIMEPART_CRLF', "\r\n");
define('IMAP_MEETING_USE_CALDAV', true);

?>
