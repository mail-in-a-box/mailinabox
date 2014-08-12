<?php
/***********************************************
* File      :   config.php
* Project   :   Z-Push
* Descr     :   CalDAV backend configuration file
************************************************/

define('CALDAV_SERVER', 'https://localhost');
define('CALDAV_PORT', '443');
define('CALDAV_PATH', '/caldav/calendars/%u/');
define('CALDAV_PERSONAL', '');

// If the CalDAV server supports the sync-collection operation
// DAViCal and SOGo support it
// Setting this to false will work with most servers, but it will be slower
define('CALDAV_SUPPORTS_SYNC', false);

?>
