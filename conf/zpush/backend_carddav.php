<?php
/***********************************************
* File      :   config.php
* Project   :   Z-Push
* Descr     :   CardDAV backend configuration file
************************************************/


define('CARDDAV_PROTOCOL', 'https'); /* http or https */
define('CARDDAV_SERVER', 'localhost');
define('CARDDAV_PORT', '443');
define('CARDDAV_PATH', '/carddav/addressbooks/%u/');
define('CARDDAV_DEFAULT_PATH', '/carddav/addressbooks/%u/contacts/'); /* subdirectory of the main path */
define('CARDDAV_GAL_PATH', ''); /* readonly, searchable, not syncd */
define('CARDDAV_GAL_MIN_LENGTH', 5);
define('CARDDAV_CONTACTS_FOLDER_NAME', '%u Addressbook');


// If the CardDAV server supports the sync-collection operation
// Setting this to false will work with most servers, but it will be slower: 1 petition for the href of vcards, and 1 petition for each vcard
define('CARDDAV_SUPPORTS_SYNC', true);


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
