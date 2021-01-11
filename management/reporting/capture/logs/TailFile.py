import threading
import os
import logging
import stat

from .ReadLineHandler import ReadLineHandler

log = logging.getLogger(__name__)

'''Spawn a thread to "tail" a log file. For each line read, provided
callbacks do something with the output. Callbacks must be a subclass
of ReadLineHandler.

'''

class TailFile(threading.Thread):
    def __init__(self, log_file, store=None):
        ''' log_file - the log file to monitor
            store - a ReadPositionStore instance
        '''
        self.log_file = log_file
        self.store = store

        self.fp = None
        self.inode = None
        self.callbacks = []
        self.interrupt = threading.Event()

        name=f'{__name__}-{os.path.basename(log_file)}'
        log.debug('init thread: %s', name)
        super(TailFile, self).__init__(name=name, daemon=True)
        
    def stop(self, do_join=True):
        log.debug('TailFile stopping')
        self.interrupt.set()
        # close must be called to unblock the thread fp.readline() call
        self._close()
        if do_join:
            self.join()

    def __del__(self):
        self.stop(do_join=False)

    def add_handler(self, fn):
        assert self.is_alive() == False
        self.callbacks.append(fn)

    def clear_callbacks(self):
        assert self.is_alive() == False
        self.callbacks = []

    def _open(self):
        self._close()
        self.inode = os.stat(self.log_file)[stat.ST_INO]
        self.fp = open(
            self.log_file,
            "r",
            encoding="utf-8",
            errors="backslashreplace"
        )

    def _close(self):        
        if self.fp is not None:
            self.fp.close()
        self.fp = None

    def _is_rotated(self):
        try:
            return os.stat(self.log_file)[stat.ST_INO] != self.inode
        except FileNotFoundError:
            return False

    def _issue_callbacks(self, line):
        for cb in self.callbacks:
            if isinstance(cb, ReadLineHandler):
                cb.handle(line)
            else:
                cb(line)

    def _notify_end_of_callbacks(self):
        for cb in self.callbacks:
            if isinstance(cb, ReadLineHandler):
                cb.end_of_callbacks(self)

    def _restore_read_position(self):
        if self.fp is None:
            return
        
        if self.store is None:
            self.fp.seek(
                0,
                os.SEEK_END
            )
        else:
            pos = self.store.get(self.log_file, self.inode)
            size = os.stat(self.log_file)[stat.ST_SIZE]
            if size < pos:
                log.debug("truncated: %s" % self.log_file)
                self.fp.seek(0, os.SEEK_SET)
            else:
                # if pos>size here, the seek call succeeds and returns
                # 'pos', but future reads will fail
                self.fp.seek(pos, os.SEEK_SET)
        
    def run(self):
        self.interrupt.clear()

        # initial open - wait until file exists
        while not self.interrupt.is_set() and self.fp is None:
            try:
                self._open()
            except FileNotFoundError:
                log.debug('log file "%s" not found, waiting...', self.log_file)
                self.interrupt.wait(2)
                continue

        # restore reading position
        self._restore_read_position()
        
        while not self.interrupt.is_set():                
            try:
                line = self.fp.readline() # blocking
                if line=='':
                    log.debug('got EOF')
                    # EOF - check if file was rotated
                    if self._is_rotated():
                        log.debug('rotated')
                        self._open()
                        if self.store is not None:
                            self.store.clear(self.log_file)
                            
                    # if not rotated, sleep
                    else:
                        self.interrupt.wait(1)
                        
                else:
                    # save position and call all callbacks
                    if self.store is not None:
                        self.store.save(
                            self.log_file,
                            self.inode,
                            self.fp.tell()
                        )
                    self._issue_callbacks(line)

            except Exception as e:
                log.exception(e)
                if self.interrupt.wait(1) is not True:
                    if self._is_rotated():
                        self._open()


        self._close()

        try:
            self._notify_end_of_callbacks()
        except Exception as e:
            log.exception(e)
            
        
