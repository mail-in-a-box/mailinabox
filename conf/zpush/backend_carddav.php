<?php
/***********************************************
* File      :   config.php
* Project   :   Z-Push
* Descr     :   CardDAV backend configuration file
************************************************/


define('CARDDAV_PROTOCOL', 'https'); /* http or https */
define('CARDDAV_SERVER', '127.0.0.1');
define('CARDDAV_PORT', '443');
define('CARDDAV_PATH', '/dav/principals/users/%u/');
define('CARDDAV_DEFAULT_PATH', '/dav/principals/users/%u/'); /* subdirectory of the main path */
define('CARDDAV_GAL_PATH', ''); /* readonly, searchable, not syncd */
define('CARDDAV_GAL_MIN_LENGTH', 5);
define('CARDDAV_CONTACTS_FOLDER_NAME', '%u Addressbook');
define('CARDDAV_SUPPORTS_SYNC', false);

// If the CardDAV server supports the FN attribute for searches
// DAViCal supports it, but SabreDav, Owncloud and SOGo don't
// Setting this to true will search by FN. If false will search by sn, givenName and email
// It's safe to leave it as false
define('CARDDAV_SUPPORTS_FN_SEARCH', false);


// If your carddav server needs to use file extension to recover a vcard.
//    Davical needs it
//    SOGo official demo online needs it, but some SOGo installation don't need it, so test it
define('CARDDAV_URL_VCARD_EXTENSION', '.vcf');

?>
