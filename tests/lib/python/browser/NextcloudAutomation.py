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
from .NcContactsAutomation import NcContactsAutomation

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
        submit = d.find_el('button[type="submit"]', throws=False)
        # submit button for nextcloud < 25 (jquery)
        if not submit: submit = d.find_el('#submit-wrapper') # nc<25
        submit.click()

    def logout(self):
        d = self.d
        d.say("Logout of Nextcloud")
        d.find_el('#settings .avatardiv').click()
        d.find_el('[data-id="logout"] a').click()

    def open_contacts(self):
        d = self.d
        d.say("Open contacts")
        # nc 25+
        el = d.find_el('header [data-app-id="contacts"]', throws=False)
        if not el:
            # nc < 25
            el = d.find_el('header [data-id="contacts"]')
        self.close_first_run_wizard()
        el.click()
        return NcContactsAutomation(self)

    def wait_for_app_load(self, secs=7):
        d = self.d
        d.say("Wait for app to load")

        # some apps are vue, some jquery (legacy)
        vue = d.find_el('#app-content-vue', throws=False)
        if not vue: vue = d.find_el('#app-dashboard', throws=False)
        jquery = d.find_el('#app-content', throws=False)
        
        if vue:
            d.wait_tick(1000)
            
        elif jquery:
            d.say_verbose('Waiting on a jquery app')
            d.wait_until_true('return window.$.active == 0', secs=secs)
            
        else:            
            raise NoSuchElementException('#app-dashboard, #app-content or #app-content-vue')

    def close_first_run_wizard(self):
        d = self.d
        firstrunwiz = d.find_el('#firstrunwizard', throws=False, quiet=True)
        if firstrunwiz and firstrunwiz.is_displayed():
            d.say_verbose("closing first run wizard")
            d.find_el('#firstrunwizard span.close-icon').click()
            d.wait_tick(1)
