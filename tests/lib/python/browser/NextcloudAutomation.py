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

class NextcloudAutomation(object):
    def __init__(self, d):
        ''' `d` is a browser.automation TestDriver object '''
        self.d = d
        
    def wait_for_login_screen(self, secs=7):
        d = self.d
        d.say("Wait for login screen")
        d.wait_for_el('form[name=login] input#user', secs=secs)

    def login(self, login, pw):
        d = self.d
        d.say("Login %s to Nextcloud", login)
        d.find_el('input#user').send_text(login)
        d.find_el('input#password').send_text(pw)
        d.find_el('#submit-wrapper').click()

    def logout(self):
        d = self.d
        d.say("Logout of Nextcloud")
        d.find_el('header .avatardiv').click()
        d.find_el('[data-id="logout"] a').click()

    def open_contacts(self):
        d = self.d
        d.say("Open contacts")
        d.find_el('header [data-id="contacts"]').click()

    def wait_for_app_load(self, secs=7):
        d = self.d
        d.say("Wait for app to load")
        
        # some apps are vue, some jquery
        vue = d.find_el('#app-content-vue', throws=False)
        jquery = d.find_el('#app-content', throws=False)
        
        if vue:
            d.say_verbose('Waiting on a vue app')
            d.execute_script('window.qa_app_loaded=false; window.setTimeout(() => { window.qa_app_loaded=true; }, 1000)');
            d.wait_until_true('return window.qa_app_loaded === true', secs=secs)
            
        elif jquery:
            d.say_verbose('Waiting on a jquery app')
            d.wait_until_true('return window.$.active == 0', secs=secs)
            
        else:
            raise NoSuchElementException('#app-content or #app-content-vue')

    def click_contact(self, contact):
        d = self.d
        d.say("Click contact %s", contact['email'])
        found = False
        els = d.find_els('div.contacts-list div.option__details')
        d.say_verbose('found %s contacts' % len(els))
        for el in els:
            fullname = el.find_el('.option__lineone').content().strip()
            email = el.find_el('.option__linetwo').content().strip()
            d.say_verbose('contact: "%s" <%s>', fullname, email)
            if fullname.lower() == "%s %s" % (contact['givenname'].lower(), contact['surname'].lower()) and email.lower() == contact['email'].lower():
                found = True
                el.click()
                break
        if not found: raise NoSuchElementException()

    def wait_contact_loaded(self, secs=5):
        d = self.d
        d.wait_for_el('section.contact-details', secs=secs)
        
