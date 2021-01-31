'''subclass this and override all methods to persist the position of
the log file that has been processed so far.

this enables the log monitor to pick up where it left off

a single FilePositionStore can safely be used with multiple
LogMonitor instances

'''
class ReadPositionStore(object):
    def get(self, log_file, inode):
        '''return the offset from the start of the file of the last
        position saved for log_file having the given inode, or zero if
        no position is currently saved

        '''
        raise NotImplementedError()

    def save(self, log_file, inode, offset):
        '''save the current position'''
        raise NotImplementedError()

    def clear(self, log_file):
        '''remove all entries for `log_file`'''
        raise NotImplementedError()
    
