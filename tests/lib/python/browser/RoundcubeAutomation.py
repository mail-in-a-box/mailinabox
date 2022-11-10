#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####


class RoundcubeAutomation(object):
    def __init__(self, d):
        ''' `d` is a browser.automation TestDriver object '''
        self.d = d
        
    def wait_for_login_screen(self, secs=5):
        d = self.d
        d.say("Wait for login screen")
        d.wait_for_el('#rcmloginuser', secs=secs)

    def login(self, login, pw):
        d = self.d
        d.say("Login %s to roundcube", login)
        d.find_el('#rcmloginuser').send_text(login)
        d.find_el('#rcmloginpwd').send_text(pw)
        d.find_el('#rcmloginsubmit').click()
        
    def logout(self):
        d = self.d
        d.say("Logout of roundcube")
        el = d.wait_for_el('a.logout', must_be_enabled=True).click()

    def open_inbox(self):
        d = self.d
        d.say("Open inbox")
        d.find_el('a.mail').click()
        
    def wait_for_inbox(self, secs=10):
        d = self.d
        d.say("Wait for inbox")
        d.wait_for_el('body.task-mail')
        d.wait_for_el('a.logout', must_be_enabled=True, secs=secs)

    def open_settings(self):
        d = self.d
        d.say("Open settings")
        d.find_el('a.settings').click()

    def wait_for_settings(self, secs=10):
        d = self.d
        d.say("Wait for settings")
        d.wait_for_el('body.task-settings', secs=secs)

    def open_contacts(self):
        d = self.d
        d.say("Open contacts")
        d.find_el('a.contacts').click()

    def wait_for_contacts(self, secs=10):
        d = self.d
        d.say("Wait for contacts")
        d.wait_for_el('body.task-addressbook', secs=secs)

