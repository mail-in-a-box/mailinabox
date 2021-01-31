# -*- indent-tabs-mode: t; tab-width: 4; python-indent-offset: 4; -*-

import threading
import queue
import logging
from .Prunable import Prunable

log = logging.getLogger(__name__)


'''subclass this and override:

    write_rec()
    read_rec()

to provide storage for event "records"

EventStore is thread safe and uses a single thread to write all
records.

'''

class EventStore(Prunable):
	def __init__(self, db_conn_factory):
		self.db_conn_factory = db_conn_factory
		# we'll have a single thread do all the writing to the database
		#self.queue = queue.SimpleQueue()  # available in Python 3.7+
		self.queue = queue.Queue()
		self.interrupt = threading.Event()
		self.rec_added = threading.Event()
		self.have_event = threading.Event()
		self.t = threading.Thread(
			target=self._bg_writer,
			name="EventStore",
			daemon=True
		)
		self.max_queue_size = 100000
		self.t.start()

	def connect(self):
		return self.db_conn_factory.connect()

	def close(self, conn):
		self.db_conn_factory.close(conn)

	def write_rec(self, conn, type, rec):
		'''write a "rec" of the given "type" to the database. The subclass
		must know how to do that. "type" is a string identifier of the
		subclass's choosing. Users of this class should call store()
		and not this function, which will queue the request and a
		thread managed by this class will call this function.

		'''
		raise NotImplementedError()
		
	def read_rec(self, conn, type, args):
		'''read from the database'''
		raise NotImplementedError()

	def prune(self, conn):
		raise NotImplementedError()
	
	def store(self, type, rec):
		self.queue.put({
			'type': type,
			'rec': rec
		})
		self.rec_added.set()
		self.have_event.set()

	def stop(self):
		self.interrupt.set()
		self.have_event.set()
		self.t.join()

	def __del__(self):
		log.debug('EventStore __del__')
		self.interrupt.set()
		self.have_event.set()

	def _pop(self):
		try:
			return self.queue.get(block=False)
		except queue.Empty:
			return None
		
	def _bg_writer(self):
		log.debug('start EventStore thread')
		conn = self.connect()
		try:
			while not self.interrupt.is_set() or not self.queue.empty():
				item = self._pop()
				if item:
					try:
						self.write_rec(conn, item['type'], item['rec'])
					except Exception as e:
						log.exception(e)
						retry_count = item.get('retry_count', 0)
						if self.interrupt.is_set():
							log.warning('interrupted, dropping record: %s',item)
						elif retry_count > 2:
							log.warning('giving up after %s attempts, dropping record: %s', retry_count, item)
						elif self.queue.qsize() >= self.max_queue_size:
							log.warning('queue full, dropping record: %s', item)
						else:
							item['retry_count'] = retry_count + 1
							self.queue.put(item)
							# wait for another record to prevent immediate retry
							if not self.interrupt.is_set():
								self.have_event.wait()
								self.rec_added.clear()
								self.have_event.clear()
					self.queue.task_done()   # remove for SimpleQueue
							
				else:
					self.have_event.wait()
					self.rec_added.clear()
					self.have_event.clear()
				
		finally:
			self.close(conn)			

