<?php
/***********************************************
* File      :   config.php
* Project   :   Z-Push
* Descr     :   Autodiscover configuration file
************************************************/

/**********************************************************************************
 *  Default settings
 */
    // Defines the base path on the server
    define('BASE_PATH', dirname($_SERVER['SCRIPT_FILENAME']). '/');

    // The Z-Push server location for the autodiscover response
    define('SERVERURL', 'https://'.$_SERVER['SERVER_NAME'].'/Microsoft-Server-ActiveSync');

    define('USE_FULLEMAIL_FOR_LOGIN', true);

    define('LOGFILEDIR', '/var/log/z-push/');
    define('LOGFILE', LOGFILEDIR . 'autodiscover.log');
    define('LOGERRORFILE', LOGFILEDIR . 'autodiscover-error.log');
    define('LOGLEVEL', LOGLEVEL_INFO);
    define('LOGUSERLEVEL', LOGLEVEL);
/**********************************************************************************
 *  Backend settings
 */
    // the backend data provider
    define('BACKEND_PROVIDER', 'BackendCombined');
?>