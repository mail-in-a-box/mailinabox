#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####

from daemon import app
import auth, utils

app.logger.addHandler(utils.create_syslog_handler())

if __name__ == "__main__":
    app.run(port=10222)