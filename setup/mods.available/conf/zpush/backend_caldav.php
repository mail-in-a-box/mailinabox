<?php
/***********************************************
* File      :   config.php
* Project   :   Z-Push
* Descr     :   CalDAV backend configuration file
************************************************/

define('CALDAV_PROTOCOL', 'NC_PROTO');
define('CALDAV_SERVER', 'NC_HOST');
define('CALDAV_PORT', 'NC_PORT');
define('CALDAV_PATH', 'NC_PREFIX/remote.php/dav/calendars/%u/');
define('CALDAV_PERSONAL', 'PRINCIPAL');
define('CALDAV_SUPPORTS_SYNC', false);
define('CALDAV_MAX_SYNC_PERIOD', 2147483647);

?>
