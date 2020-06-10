#!/usr/bin/env php
<?php

define('INSTALL_PATH', realpath(__DIR__ . '/..') . '/' );

require_once INSTALL_PATH.'program/include/clisetup.php';
ini_set('memory_limit', -1);



function usage()
{
    print "Usage: carddav_refresh.sh [-id <number>] username password\n";
    print "Force a sync of a user's addressbook with the remote server\n";
    print "Place this script in /path/to/roundcubemail/bin, then change the working directory to /path/to/roundcubemail, then run ./bin/cardav_refresh.sh"; 
    exit(1);
}

function _die($msg)
{
    fwrite(STDERR, $msg . "\n");
    exit(1);
}

$args = rcube_utils::get_opt(array('id' => 'dbid'));

$dbid = 0;
if (!empty($args['dbid'])) {
    $dbid = intval($args['dbid']);
}
   
$username = trim($args[0]);
if (empty($username)) {
    print "Missing username";
    usage();
}
$password = trim($args[1]);
if (empty($password)) {
    usage();
}


// -----
// From index.php -- initialization and login
// -----

// init application, start session, init output class, etc.
$RCMAIL = rcmail::get_instance(0, $GLOBALS['env']);

// trigger startup plugin hook
$startup = $RCMAIL->plugins->exec_hook('startup', array('task' => $RCMAIL->task, 'action' => $RCMAIL->action));
$RCMAIL->set_task($startup['task']);
$RCMAIL->action = $startup['action'];
$auth = $RCMAIL->plugins->exec_hook('authenticate', array(
            'host'  => $RCMAIL->autoselect_host(),
            'user'  => $username,
            'pass'  => $password,
            'valid' => true,
            'cookiecheck' => false,));

// Login
if ($auth['valid'] && !$auth['abort']
    && $RCMAIL->login($auth['user'], $auth['pass'], $auth['host'], $auth['cookiecheck']))
  {
    print "login ok\n";
  }
 else
   {
     _die("login failed");
   }

 
// ----------------------------------------------------
// ensure the carddav tables are created and populated
// ----------------------------------------------------

require_once('plugins/carddav/carddav_backend.php');
require_once('plugins/carddav/carddav.php');

$c = new carddav(rcube_plugin_api::get_instance());
$c->task .= "|cli";
$c->init();
print "done: init\n";
// this ensures the carddav tables are created
$c->checkMigrations();
print "done: init tables\n";
// this populates carddav_addressbooks from config
$c->init_presets();
print "done: init addressbooks\n";

// -------------------------------------------------------------
// Set the last_updated field for addressbooks to an old date.
// That will force a sync/update
// -------------------------------------------------------------
$db = $rcmail->get_dbh();
$db->db_connect('w');
if (!$db->is_connected() || $db->is_error()) {
  _die("No DB connection\n" . $db->is_error());
}
print "db connected\n";

$db->query("update " . $db->table_name('carddav_addressbooks') . " set last_updated=? WHERE active=1", '2000-01-01 00:00:00');
print "update made\n";
if ($db->is_error()) {
  _die("DB error occurred: " . $db->is_error());
}


// ------------------------------------------------------
// Update/sync all active address books
// ------------------------------------------------------

// first get all row ids
$dbid=array();
$sql_result = $db->query('SELECT id FROM ' .
           $db->table_name('carddav_addressbooks') .
           ' WHERE active=1');
if ($db->is_error()) {
  _die("DB error occurred: " . $db->is_error());
}
   
while ($row = $db->fetch_assoc($sql_result)) {
  $dbid += array(intval($row['id']));
  print "carddav_addressbooks id: " . $row['id'] . "\n";
}

// instantiating carddav_backend causes the update/sync
foreach($dbid as $id) {
  $config = carddav_backend::carddavconfig($id);
  if ($config['needs_update']) {
    print "instantiating carddav_backend: " . $id . "\n";
    $b = new carddav_backend($id);
    print("success\n");
  }
}

