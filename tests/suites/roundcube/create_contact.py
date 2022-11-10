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
    NoSuchElementException,
    ElementNotInteractableException,
)
from browser.RoundcubeAutomation import RoundcubeAutomation
import sys

login = sys.argv[1]
pw = sys.argv[2]
address_book = sys.argv[3]
contact = {
    'givenname': sys.argv[4],
    'surname': sys.argv[5],
    'email': sys.argv[6],
}

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
    rcm.login(login, pw)
    rcm.wait_for_inbox()

    #
    # add contact
    #
    d.start("Add contact")
    rcm.open_contacts()
    rcm.wait_for_contacts()

    d.say("Select address book '%s'", address_book)
    el = d.find_text(address_book, "a", exact=True, throws=False, case_sensitive=True)
    if not el:
        el = d.find_text(address_book + ' (Contacts)', "a", exact=True, case_sensitive=True)
    if not el.is_displayed():
        d.say_verbose("open sidebar to select address book")
        d.find_el('a.back-sidebar-button').click()
    el.click()

    d.say("Create contact")
    d.find_el('a.create').click()
    iframe_el = d.wait_for_el('#contact-frame', secs=5)
    d.switch_to_frame(iframe_el)
    
    d.find_el('#ff_firstname').send_text(contact['givenname'])
    d.find_el('#ff_surname').send_text(contact['surname'])
    d.find_el('#ff_email0').send_text(contact['email'])
    d.find_el('button[value=Save]').click()    # save new password
    d.switch_to_window(d.get_current_window_handle())
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
