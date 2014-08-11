<?php
/***********************************************
* File      :   config.php
* Project   :   Z-Push
* Descr     :   CardDAV backend configuration file
*
* Created   :   16.03.2013
*
* Copyright 2007 - 2013 Zarafa Deutschland GmbH
*
* This program is free software: you can redistribute it and/or modify
* it under the terms of the GNU Affero General Public License, version 3,
* as published by the Free Software Foundation with the following additional
* term according to sec. 7:
*
* According to sec. 7 of the GNU Affero General Public License, version 3,
* the terms of the AGPL are supplemented with the following terms:
*
* "Zarafa" is a registered trademark of Zarafa B.V.
* "Z-Push" is a registered trademark of Zarafa Deutschland GmbH
* The licensing of the Program under the AGPL does not imply a trademark license.
* Therefore any rights, title and interest in our trademarks remain entirely with us.
*
* However, if you propagate an unmodified version of the Program you are
* allowed to use the term "Z-Push" to indicate that you distribute the Program.
* Furthermore you may use our trademarks where it is necessary to indicate
* the intended purpose of a product or service provided you use it in accordance
* with honest practices in industrial or commercial matters.
* If you want to propagate modified versions of the Program under the name "Z-Push",
* you may only do so if you have a written permission by Zarafa Deutschland GmbH
* (to acquire a permission please contact Zarafa at trademark@zarafa.com).
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
* GNU Affero General Public License for more details.
*
* You should have received a copy of the GNU Affero General Public License
* along with this program.  If not, see <http://www.gnu.org/licenses/>.
*
* Consult LICENSE file for details
************************************************/

// ************************
//  BackendCardDAV settings
// ************************

// Server protocol: http or https
define('CARDDAV_PROTOCOL', 'https');

// Server name
define('CARDDAV_SERVER', 'localhost');

// Server port
define('CARDDAV_PORT', '443');

// Server path to the addressbook, or the principal with the addressbooks
//  If your user has more than 1 addressbook point it to the principal.
//  Example: user test@domain.com will have 2 addressbooks
//      http://localhost/caldav.php/test@domain.com/addresses/personal
//      http://localhost/caldav.php/test@domain.com/addresses/work
//      You set the CARDDAV_PATH to '/caldav.php/%u/addresses/' and personal and work will be autodiscovered
// %u: replaced with the username
// %d: replaced with the domain
//   Add the trailing /
define('CARDDAV_PATH', '/remote.php/carddav/addressbooks/%u/');


// Server path to the default addressbook
//  Mobile device will create new contacts here. It must be under CARDDAV_PATH
// %u: replaced with the username
// %d: replaced with the domain
//   Add the trailing /
define('CARDDAV_DEFAULT_PATH', '/remote.php/carddav/addressbooks/%u/contacts/');

// Server path to the GAL addressbook. This addressbook is readonly and searchable by the user, but it will NOT be synced.
// If you don't want GAL, comment it
// %u: replaced with the username
// %d: replaced with the domain
//  Add the trailing /
define('CARDDAV_GAL_PATH', '/caldav.php/%d/GAL/');

// Minimal length for the search pattern to do the real search.
define('CARDDAV_GAL_MIN_LENGTH', 5);

// Addressbook display name, the name showed in the mobile device
// %u: replaced with the username
// %d: replaced with the domain
define('CARDDAV_CONTACTS_FOLDER_NAME', '%u Addressbook');


// If the CardDAV server supports the sync-collection operation
// DAViCal supports it, but SabreDav, Owncloud, SOGo don't
// Setting this to false will work with most servers, but it will be slower: 1 petition for the href of vcards, and 1 petition for each vcard
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