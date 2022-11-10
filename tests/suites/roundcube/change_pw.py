#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####

from browser.automation import (
    TestDriver,
    TimeoutException,
    NoSuchElementException
)
from browser.RoundcubeAutomation import RoundcubeAutomation
import sys

login = sys.argv[1]
old_pw = sys.argv[2]
new_pw = sys.argv[3]

d = TestDriver()
rcm = RoundcubeAutomation(d)

try:
    #
    # open the browser to roundcube
    #
    d.start("Opening roundcube")
    d.get("/mail/")
    rcm.wait_for_login_screen(secs=10)

    #
    # login
    #
    rcm.login(login, old_pw)
    rcm.wait_for_inbox()

    #
    # change password
    #
    d.start("Change password")
    rcm.open_settings()
    rcm.wait_for_settings()
    
    d.say("Enter new password")
    d.find_el('a.password').click() # open the change password section
    d.wait_for_el('button[value=Save]') # wait for it to load
    d.find_el('#curpasswd').send_text(old_pw) # fill old password
    d.find_el('#newpasswd').send_text(new_pw) # fill new password
    d.find_el('#confpasswd').send_text(new_pw) # fill confirm password
    d.find_el('button[value=Save]').click()    # save new password
    d.wait_for_text("Successfully saved", secs=5, case_sensitive=False)

    #
    # logout
    #
    rcm.logout()
    
    #
    # done
    #
    d.say("Success!")

except Exception as e:
    d.fail(e)
    raise

finally:
    d.quit()
