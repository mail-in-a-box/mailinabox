<?php
/***********************************************
* File      :   config.php
* Project   :   Z-Push
* Descr     :   Autodiscover configuration file
************************************************/

define('TIMEZONE', '');

// Defines the base path on the server
define('BASE_PATH', dirname($_SERVER['SCRIPT_FILENAME']). '/');

define('ZPUSH_HOST', 'PRIMARY_HOSTNAME');

define('USE_FULLEMAIL_FOR_LOGIN', true);

define('LOGFILEDIR', '/var/log/z-push/');
define('LOGFILE', LOGFILEDIR . 'autodiscover.log');
define('LOGERRORFILE', LOGFILEDIR . 'autodiscover-error.log');
define('LOGLEVEL', LOGLEVEL_INFO);
define('LOGUSERLEVEL', LOGLEVEL);
$specialLogUsers = array();

// the backend data provider
define('BACKEND_PROVIDER', 'BackendCombined');
?>
