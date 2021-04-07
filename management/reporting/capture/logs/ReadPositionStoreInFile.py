from .ReadPositionStore import ReadPositionStore

import threading
import json
import os
import logging

log = logging.getLogger(__name__)


class ReadPositionStoreInFile(ReadPositionStore):
    def __init__(self, output_file):
        self.output_file = output_file
        self.changed = False
        self.lock = threading.Lock()
        self.interrupt = threading.Event()

        if os.path.exists(output_file):
            with open(output_file, "r", encoding="utf-8") as fp:
                self.db = json.loads(fp.read())
        else:
            self.db = {}

        self.t = threading.Thread(
            target=self._persist_bg,
            name="ReadPositionStoreInFile",
            daemon=True
        )
        self.t.start()

    def __del__(self):
        self.interrupt.set()

    def stop(self):
        self.interrupt.set()
        self.t.join()
        
    def get(self, file, inode):
        with self.lock:
            if file in self.db and str(inode) in self.db[file]:
                return self.db[file][str(inode)]
        return 0            
    
    def save(self, file, inode, pos):
        with self.lock:
            if not file in self.db:
                self.db[file] = { str(inode):pos }
            else:
                self.db[file][str(inode)] = pos
            self.changed = True
    
    def clear(self, file):
        with self.lock:
            self.db[file] = {}
            self.changed = True


    def persist(self):
        if self.changed:
            try:
                with open(self.output_file, "w") as fp:
                    with self.lock:
                        json_str = json.dumps(self.db)
                        self.changed = False
                        
                    try:
                        fp.write(json_str)
                    except Exception as e:
                        with self.lock:
                            self.changed = True
                        log.error(e)
                        
            except Exception as e:
                log.error(e)

        
    def _persist_bg(self):
        while not self.interrupt.is_set():
            # wait 60 seconds before persisting
            self.interrupt.wait(60)
            # even if interrupted, persist one final time
            self.persist()
                        
