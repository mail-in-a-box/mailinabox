
import threading
import logging

log = logging.getLogger(__name__)


class Pruner(object):
    '''periodically calls the prune() method of registered Prunable
    objects

    '''
    def __init__(self, db_conn_factory, policy={
            'older_than_days': 7,
            'frequency_min': 60
    }):
        self.db_conn_factory = db_conn_factory
        self.policy = policy
        self.prunables = []
        self.interrupt = threading.Event()
        self._new_thread()
        self.t.start()


    def _new_thread(self):
        self.interrupt.clear()
        self.t = threading.Thread(
            target=self._bg_pruner,
	    name="Pruner",
	    daemon=True
        )
        
    def add_prunable(self, inst):
        self.prunables.append(inst)

    def set_policy(self, policy):
        self.stop()
        self.policy = policy
        # a new thread object must be created or Python(<3.8?) throws
        # RuntimeError("threads can only be started once")
        self._new_thread()
        self.t.start()

    def stop(self, do_join=True):
        self.interrupt.set()
        if do_join:
            self.t.join()

    def connect(self):
        return self.db_conn_factory.connect()

    def close(self, conn):
        self.db_conn_factory.close(conn)
                
    def __del__(self):
        self.stop(do_join=False)
    
    def _bg_pruner(self):
        conn = self.connect()

        def do_prune():
            for prunable in self.prunables:
                if not self.interrupt.is_set():
                    try:
                        prunable.prune(conn, self.policy)
                    except Exception as e:
                        log.exception(e)
                        
        try:
            # prune right-off
            do_prune()
            
            while not self.interrupt.is_set():
                # wait until interrupted or it's time to prune
                if self.interrupt.wait(self.policy['frequency_min'] * 60) is not True:
                    do_prune()

        finally:
            self.close(conn)
