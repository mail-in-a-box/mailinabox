#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####


'''subclass this and override methods to handle log output'''
class ReadLineHandler(object):
    def handle(self, line):
        ''' handle a single line of output '''
        raise NotImplementedError()
    
    def end_of_callbacks(self, thread):
        '''called when no more output will be sent to handle(). override this
        method to save state, or perform cleanup during this
        callback

        '''
        pass
    
