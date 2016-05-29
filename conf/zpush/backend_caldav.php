<?php
/***********************************************
* File      :   config.php
* Project   :   Z-Push
* Descr     :   CalDAV backend configuration file
************************************************/

define('CALDAV_PROTOCOL', 'https');
define('CALDAV_SERVER', '127.0.0.1');
define('CALDAV_PORT', '443');
define('CALDAV_PATH', '/dav/principals/%u/');
define('CALDAV_PERSONAL', 'PRINCIPAL');
define('CALDAV_SUPPORTS_SYNC', false);
define('CALDAV_MAX_SYNC_PERIOD', 2147483647);

?>
