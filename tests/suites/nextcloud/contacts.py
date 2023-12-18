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
from browser.NextcloudAutomation import NextcloudAutomation
import sys

op = sys.argv[1]
login = sys.argv[2]
pw = sys.argv[3]
contact = {
    'givenname': sys.argv[4],
    'surname': sys.argv[5],
    'email': sys.argv[6],
}

d = TestDriver()
nc = NextcloudAutomation(d)

try:
    #
    # open the browser to Nextcloud
    #
    # these tests work for both remote and local Nextclouds. nginx
    # will redirect to a remote nextcloud during get(), if configured
    #
    d.start("Opening Nextcloud")
    d.get("/cloud/")
    nc.wait_for_login_screen()
    d.say_verbose('url: ' + d.current_url())

    #
    # login
    #
    nc.login(login, pw)
    nc.wait_for_app_load()

    #
    # open Contacts
    #
    d.start("Open contacts app")
    contacts = nc.open_contacts()
    nc.wait_for_app_load()

    #
    # handle selected operation 
    #
    if op=='exists':
        d.start("Check that contact %s exists", contact['email'])
        contacts.click_contact(contact) # raises NoSuchElementException if not found
        
    elif op=='delete':
        d.start("Delete contact %s", contact['email'])
        contacts.click_contact(contact)
        contacts.wait_contact_loaded()
        contacts.delete_current_contact()

    elif op=='nop':
        pass
        
    else:
        raise ValueError('Invalid operation: %s' % op)

    #
    # logout
    #
    d.start("Logout")
    nc.logout()
    nc.wait_for_login_screen()

    #
    # done
    #
    d.start("Success!")

except Exception as e:
    d.fail(e)
    raise

finally:
    d.quit()
