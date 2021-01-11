
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
    
