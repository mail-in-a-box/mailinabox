import datetime
import threading

#
# thread-safe dict cache
#

class DictCache(object):
    def __init__(self, valid_for):
        '''`valid_for` must be a datetime.timedelta object indicating how long
        a cache item is valid

        '''
        self.obj = None
        self.time = None
        self.valid_for = valid_for
        self.guard = threading.Lock()

    def get(self):
        now = datetime.datetime.now()
        with self.guard:
            if self.obj and (now - self.time) <= self.valid_for:
                return self.obj.copy()

    def set(self, obj):
        with self.guard:
            self.obj = obj.copy()
            self.time = datetime.datetime.now()

    def reset(self):
        with self.guard:
            self.obj = None
            self.time = None
