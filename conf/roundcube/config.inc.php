<?php
/*
 * Do not edit. Written by Mail-in-a-Box. Regenerated on updates.
 */
$config = array();
$config['log_dir'] = '/var/log/roundcubemail/';
$config['temp_dir'] = '/var/tmp/roundcubemail/';
$config['db_dsnw'] = 'sqlite:////home/user-data/mail/roundcube/roundcube.sqlite?mode=0640';
$config['default_host'] = 'ssl://localhost';
$config['default_port'] = 993;
$config['imap_conn_options'] = array(
  'ssl'         => array(
     'verify_peer'  => false,
     'verify_peer_name'  => false,
   ),
 );
$config['imap_timeout'] = 15;
$config['smtp_server'] = 'tls://127.0.0.1';
$config['smtp_port'] = 587;
$config['smtp_user'] = '%u';
$config['smtp_pass'] = '%p';
$config['smtp_conn_options'] = array(
  'ssl'         => array(
     'verify_peer'  => false,
     'verify_peer_name'  => false,
   ),
 );
$config['support_url'] = 'https://mailinabox.email/';
$config['product_name'] = 'box.supplee.com Webmail';
$config['des_key'] = 'eE4MCgtZQwgVZVBalTwPWMaC';
$config['plugins'] = array('html5_notifier', 'archive', 'zipdownload', 'password', 'managesieve', 'jqueryui', 'persistent_login', 'carddav');
$config['skin'] = 'larry';
$config['login_autocomplete'] = 2;
$config['password_charset'] = 'UTF-8';
$config['junk_mbox'] = 'Spam';
$config['quota_zero_as_unlimited'] = true;
?>
