<?php
/***********************************************
* File      :   config.php
* Project   :   Z-Push
* Descr     :   CalDAV backend configuration file
************************************************/

define('CALDAV_PROTOCOL', 'https');
define('CALDAV_SERVER', 'localhost');
define('CALDAV_PORT', '443');
define('CALDAV_PATH', '/caldav/calendars/%u/');
define('CALDAV_PERSONAL', 'PRINCIPAL');
define('CALDAV_SUPPORTS_SYNC', false);
define('CALDAV_MAX_SYNC_PERIOD', 2147483647);

?>
