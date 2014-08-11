<?php
/***********************************************
* File      :   backend/combined/config.php
* Project   :   Z-Push
* Descr     :   configuration file for the
*               combined backend.
*
* Created   :   29.11.2010
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

class BackendCombinedConfig {

    // *************************
    //  BackendCombined settings
    // *************************
    /**
     * Returns the configuration of the combined backend
     *
     * @access public
     * @return array
     *
     */
    public static function GetBackendCombinedConfig() {
        //use a function for it because php does not allow
        //assigning variables to the class members (expecting T_STRING)
        return array(
			//the order in which the backends are loaded.
			//login only succeeds if all backend return true on login
			//sending mail: the mail is sent with first backend that is able to send the mail
			'backends' => array(
				'i' => array(
					'name' => 'BackendIMAP',
				),
				'c' => array(
					'name' => 'BackendCalDAV',
				),
				'd' => array(
					'name' => 'BackendCardDAV',
				),
			),
			'delimiter' => '/',
			//force one type of folder to one backend
			//it must match one of the above defined backends
			'folderbackend' => array(
				SYNC_FOLDER_TYPE_INBOX => 'i',
				SYNC_FOLDER_TYPE_DRAFTS => 'i',
				SYNC_FOLDER_TYPE_WASTEBASKET => 'i',
				SYNC_FOLDER_TYPE_SENTMAIL => 'i',
				SYNC_FOLDER_TYPE_OUTBOX => 'i',
				SYNC_FOLDER_TYPE_TASK => 'c',
				SYNC_FOLDER_TYPE_APPOINTMENT => 'c',
				SYNC_FOLDER_TYPE_CONTACT => 'd',
				SYNC_FOLDER_TYPE_NOTE => 'c',
				SYNC_FOLDER_TYPE_JOURNAL => 'c',
				SYNC_FOLDER_TYPE_OTHER => 'i',
				SYNC_FOLDER_TYPE_USER_MAIL => 'i',
				SYNC_FOLDER_TYPE_USER_APPOINTMENT => 'c',
				SYNC_FOLDER_TYPE_USER_CONTACT => 'd',
				SYNC_FOLDER_TYPE_USER_TASK => 'c',
				SYNC_FOLDER_TYPE_USER_JOURNAL => 'c',
				SYNC_FOLDER_TYPE_USER_NOTE => 'c',
				SYNC_FOLDER_TYPE_UNKNOWN => 'i',
			),
			//creating a new folder in the root folder should create a folder in one backend
			'rootcreatefolderbackend' => 'i',
		);
    }
}
?>