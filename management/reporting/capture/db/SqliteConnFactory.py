#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####

import os, stat
import sqlite3
import logging
import threading

from .DatabaseConnectionFactory import DatabaseConnectionFactory

log = logging.getLogger(__name__)


class SqliteConnFactory(DatabaseConnectionFactory):
    def __init__(self, db_path):
        super(SqliteConnFactory, self).__init__()
        log.debug('factory for %s', db_path)
        self.db_path = db_path
        self.db_basename = os.path.basename(db_path)
        self.ensure_exists()

    def ensure_exists(self):
        # create the parent directory and set its permissions
        parent = os.path.dirname(self.db_path)
        if parent != '' and not os.path.exists(parent):
            os.makedirs(parent)
            os.chmod(parent,
                     stat.S_IRWXU |
                     stat.S_IRGRP |
                     stat.S_IXGRP |
                     stat.S_IROTH |
                     stat.S_IXOTH
            )

        # if the database is new, create an empty file and set file
        # permissions
        if not os.path.exists(self.db_path):
            log.debug('creating empty database: %s', self.db_basename)
            with open(self.db_path, 'w') as fp:
                pass

            os.chmod(self.db_path,
                     stat.S_IRUSR |
                     stat.S_IWUSR
            )

    def connect(self):
        log.debug('opening database %s', self.db_basename)
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def close(self, conn):
        log.debug('closing database %s', self.db_basename)
        conn.close()
