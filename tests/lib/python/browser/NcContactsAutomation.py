#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####

from selenium.common.exceptions import (
    NoSuchElementException,
)

class NcContactsAutomation(object):
    def __init__(self, nc):
        ''' `nc` is a NextcloudAutomation object '''
        self.nc = nc
        self.d = nc.d

    def click_contact(self, contact):
        d = self.d
        d.say("Click contact %s", contact['email'])
        found = False
        # .list-item-content (nc 25+)
        # .option__details (nc <25)
        els = d.find_els('div.contacts-list div.list-item-content,div.option__details')
        d.say_verbose('found %s contacts' % len(els))
        for el in els:
            # .line-one (nc 25+)
            # .option__lineone (nc <25)
            fullname = el.find_el('.line-one,.option__lineone').content().strip()
            email = el.find_el('.line-two,.option__linetwo').content().strip()
            d.say_verbose('contact: "%s" <%s>', fullname, email)
            # NC 28: email not present in html
            ignore_email = True if email == '' else False
            if fullname.lower() == "%s %s" % (contact['givenname'].lower(), contact['surname'].lower()) and ( ignore_email or email.lower() == contact['email'].lower() ):
                found = True
                el.click()
                break
        if not found: raise NoSuchElementException()

    def wait_contact_loaded(self, secs=5):
        d = self.d
        d.say("Wait for contact to load")
        d.wait_for_el('section.contact-details', secs=secs)
        
    def delete_current_contact(self):
        d = self.d
        d.say("Delete current contact")
        # Click ... menu
        d.find_el('.contact-header__actions button.action-item__menutoggle').click()
        # .v-popper__popper (nc 25+)
        # .popover (nc <25)
        el = d.wait_for_el(
            '.v-popper__popper,.popover',
            must_be_displayed=True,
            secs=2
        )
        # click "delete"
        # .delete-icon (nc 25+)
        # .icon-delete (nc <25)
        delete = el.find_el('span.delete-icon,span.icon-delete').click()
