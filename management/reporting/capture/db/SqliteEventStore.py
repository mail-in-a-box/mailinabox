# -*- indent-tabs-mode: t; tab-width: 4; python-indent-offset: 4; -*-

import sqlite3
import os, stat
import logging
import json
import datetime
from .EventStore import EventStore

log = logging.getLogger(__name__)

#
# schema
#
mta_conn_fields = [
	'service',
	'service_tid',
	'connect_time',
	'disconnect_time',
	'remote_host',
	'remote_ip',
	'sasl_method',
	'sasl_username',
	'remote_auth_success',
	'remote_auth_attempts',
	'remote_used_starttls',
	'disposition',
]

mta_accept_fields = [
	'mta_conn_id',
	'queue_time',
	'queue_remove_time',
	'subsystems',
#	'spf_tid',
	'spf_result',
	'spf_reason',
	'postfix_msg_id',
	'message_id',
	'dkim_result',
	'dkim_reason',
	'dmarc_result',
	'dmarc_reason',
	'envelope_from',
	'message_size',
	'message_nrcpt',
    'accept_status',
    'failure_info',
	'failure_category',
]

mta_delivery_fields = [
	'mta_accept_id',
	'service',
#	'service_tid',
	'rcpt_to',
	'orig_to',
#	'postgrey_tid',
	'postgrey_result',
	'postgrey_reason',
	'postgrey_delay',
#	'spam_tid',
	'spam_result',
	'spam_score',
	'relay',
    'status',
	'delay',
	'delivery_connection',
	'delivery_connection_info',
	'delivery_info',
	'failure_category',
]


db_info_create_table_stmt = "CREATE TABLE IF NOT EXISTS db_info(id INTEGER PRIMARY KEY AUTOINCREMENT, key TEXT NOT NULL, value TEXT NOT NULL)"

schema_updates = [
	# update 0
	[
		# three "mta" tables having a one-to-many-to-many relationship:
		#    mta_connection(1) -> mta_accept(0:N) -> mta_delivery(0:N)
		#

		"CREATE TABLE mta_connection(\
			mta_conn_id INTEGER PRIMARY KEY AUTOINCREMENT,\
			service TEXT NOT NULL,  /* 'smtpd', 'submission' or 'pickup' */\
			service_tid TEXT NOT NULL,\
			connect_time TEXT NOT NULL,\
			disconnect_time TEXT,\
			remote_host TEXT COLLATE NOCASE,\
			remote_ip TEXT COLLATE NOCASE,\
			sasl_method TEXT,             /* sasl: submission service only */\
			sasl_username TEXT COLLATE NOCASE,\
			remote_auth_success INTEGER,  /* count of successes */\
			remote_auth_attempts INTEGER, /* count of attempts */\
			remote_used_starttls INTEGER, /* 1 if STARTTLS used */\
			disposition TEXT     /* 'normal','scanner','login_attempt',etc */\
		)",

		"CREATE INDEX idx_mta_connection_connect_time ON mta_connection(connect_time, sasl_username COLLATE NOCASE)",


		"CREATE TABLE mta_accept(\
			mta_accept_id INTEGER PRIMARY KEY AUTOINCREMENT,\
			mta_conn_id INTEGER,\
			queue_time TEXT,\
			queue_remove_time TEXT,\
			subsystems TEXT,\
			/*spf_tid TEXT,*/\
			spf_result TEXT,\
			spf_reason TEXT,\
			postfix_msg_id TEXT,\
			message_id TEXT,\
			dkim_result TEXT,\
			dkim_reason TEXT,\
			dmarc_result TEXT,\
			dmarc_reason TEXT,\
			envelope_from TEXT COLLATE NOCASE,\
			message_size INTEGER,\
			message_nrcpt INTEGER,\
            accept_status TEXT,       /* 'accept','greylist','spf-reject',others... */\
            failure_info TEXT,        /* details from mta or subsystems */\
			failure_category TEXT,\
            FOREIGN KEY(mta_conn_id) REFERENCES mta_connection(mta_conn_id) ON DELETE RESTRICT\
		)",

		"CREATE TABLE mta_delivery(\
			mta_delivery_id INTEGER PRIMARY KEY AUTOINCREMENT,\
			mta_accept_id INTEGER,\
			service TEXT,           /* 'lmtp' or 'smtp' */\
		    /*service_tid TEXT,*/\
			rcpt_to TEXT COLLATE NOCASE,  /* email addr */\
			/*postgrey_tid TEXT,*/\
			postgrey_result TEXT,\
			postgrey_reason TEXT,\
			postgrey_delay NUMBER,\
			/*spam_tid TEXT,*/         /* spam: lmtp only */\
			spam_result TEXT,      /* 'clean' or 'spam' */\
			spam_score NUMBER,     /* eg: 2.10 */\
			relay TEXT,            /* hostname[IP]:port */\
            status TEXT,           /* 'sent', 'bounce', 'reject', etc */\
			delay NUMBER,          /* fractional seconds, 'sent' status only */\
		    delivery_connection TEXT, /* 'trusted' or 'untrusted' */\
		    delivery_connection_info TEXT, /* details on TLS connection */\
			delivery_info TEXT,    /* details from the remote mta */\
			failure_category TEXT,\
            FOREIGN KEY(mta_accept_id) REFERENCES mta_accept(mta_accept_id) ON DELETE RESTRICT\
		)",

		"CREATE INDEX idx_mta_delivery_rcpt_to ON mta_delivery(rcpt_to COLLATE NOCASE)",

		"CREATE TABLE state_cache(\
		    state_cache_id INTEGER PRIMARY KEY AUTOINCREMENT,\
		    owner_id INTEGER NOT NULL,\
            state TEXT\
		)",

		"INSERT INTO db_info (key,value) VALUES ('schema_version', '0')"
	],

	# update 1
	[
		"ALTER TABLE mta_delivery ADD COLUMN orig_to TEXT COLLATE NOCASE",
		"UPDATE db_info SET value='1' WHERE key='schema_version'"
	]

]



class SqliteEventStore(EventStore):
	
	def __init__(self, db_conn_factory):
		super(SqliteEventStore, self).__init__(db_conn_factory)
		self.update_schema()
		
	def update_schema(self):
		''' update the schema to the latest version

		'''
		c = None
		conn = None
		try:
			conn = self.connect()
			c = conn.cursor()
			c.execute(db_info_create_table_stmt)
			conn.commit()
			c.execute("SELECT value from db_info WHERE key='schema_version'")
			v = c.fetchone()
			if v is None:
				v = -1
			else:
				v = int(v[0])
			for idx in range(v+1, len(schema_updates)):
				log.info('updating database to v%s', idx)
				for stmt in schema_updates[idx]:
					try:
						c.execute(stmt)
					except Exception as e:
						log.error('problem with sql statement at version=%s error="%s" stmt="%s"' % (idx, e, stmt))
						raise e
					
			conn.commit()
			
		finally:
			if c: c.close(); c=None
			if conn: self.close(conn); conn=None
		


	def write_rec(self, conn, type, rec):
		if type=='inbound_mail':
			#log.debug('wrote inbound_mail record')
			self.write_inbound_mail(conn, rec)
		elif type=='state':
			''' rec: {
			        owner_id: int,
			        state: list
			    }
			'''
			self.write_state(conn, rec)
		else:
			raise ValueError('type "%s" not implemented' % type)


	def _insert(self, table, fields):
		insert = 'INSERT INTO ' + table + ' (' + \
			",".join(fields) + \
			') VALUES (' + \
			"?,"*(len(fields)-1) + \
			'?)'
		return insert

	def _values(self, fields, data_dict):
		values = []
		for field in fields:
			if field in data_dict:
				values.append(data_dict[field])
				data_dict.pop(field)
			else:
				values.append(None)

		for field in data_dict:
			if type(data_dict[field]) != list and not field.startswith('_') and not field.endswith('_tid'):
				log.warning('unused field: %s', field)
		return values

			
	def write_inbound_mail(self, conn, rec):
		c = None
		try:
			c = conn.cursor()
			
			# mta_connection
			insert = self._insert('mta_connection', mta_conn_fields)
			values = self._values(mta_conn_fields, rec)
			#log.debug('INSERT: %s VALUES: %s REC=%s', insert, values, rec)
			c.execute(insert, values)
			conn_id = c.lastrowid

			accept_insert = self._insert('mta_accept', mta_accept_fields)
			delivery_insert = self._insert('mta_delivery', mta_delivery_fields)
			for accept in rec.get('mta_accept', []):
				accept['mta_conn_id'] = conn_id
				values = self._values(mta_accept_fields, accept)
				c.execute(accept_insert, values)
				accept_id = c.lastrowid
				
				for delivery in accept.get('mta_delivery', []):
					delivery['mta_accept_id'] = accept_id
					values = self._values(mta_delivery_fields, delivery)
					c.execute(delivery_insert, values)

			conn.commit()

		except sqlite3.Error as e:
			conn.rollback()
			raise e
			
		finally:
			if c: c.close(); c=None
			

			
	def write_state(self, conn, rec):
		c = None
		try:
			c = conn.cursor()
			
			owner_id = rec['owner_id']
			insert = 'INSERT INTO state_cache (owner_id, state) VALUES (?, ?)'
			for item in rec['state']:
				item_json = json.dumps(item)
				c.execute(insert, (owner_id, item_json))
				
			conn.commit()

		except sqlite3.Error as e:
			conn.rollback()
			raise e
			
		finally:
			if c: c.close(); c=None

			
	def read_rec(self, conn, type, args):
		if type=='state':
			return self.read_state(
				conn,
				args['owner_id'],
				args.get('clear',False)
			)
		else:
			raise ValueError('type "%s" not implemented' % type)
		
	def read_state(self, conn, owner_id, clear):
		c = None
		state = []
		try:
			c = conn.cursor()
			select = 'SELECT state FROM state_cache WHERE owner_id=? ORDER BY state_cache_id'
			for row in c.execute(select, (owner_id,)):
				state.append(json.loads(row[0]))

			if clear:
				delete = 'DELETE FROM state_cache WHERE owner_id=?'
				c.execute(delete, (owner_id,))
				conn.commit()

		finally:
			if c: c.close(); c=None

		return state
	
	def prune(self, conn, policy):
		older_than_days = datetime.timedelta(days=policy['older_than_days'])
		if older_than_days.days <= 0:
			return
		now = datetime.datetime.now(datetime.timezone.utc)
		d = (now - older_than_days)
		dstr = d.isoformat(sep=' ', timespec='seconds')
		
		c = None
		try:
			c = conn.cursor()
			deletes = [
				'DELETE FROM mta_delivery WHERE mta_accept_id IN (\
				  SELECT mta_accept.mta_accept_id FROM mta_accept\
				  JOIN mta_connection ON mta_connection.mta_conn_id = mta_accept.mta_conn_id\
				  WHERE connect_time < ?)',

				'DELETE FROM mta_accept WHERE mta_accept_id IN (\
				  SELECT mta_accept.mta_accept_id FROM mta_accept\
				  JOIN mta_connection ON mta_connection.mta_conn_id = mta_accept.mta_conn_id\
				  WHERE connect_time < ?)',

				'DELETE FROM mta_connection WHERE connect_time < ?'
			]

			counts = []
			for delete in deletes:
				c.execute(delete, (dstr,))
				counts.append(str(c.rowcount))
			conn.commit()
			counts.reverse()
			log.info("pruned %s rows", "/".join(counts))

		except sqlite3.Error as e:
			conn.rollback()
			raise e
				
		finally:
			if c: c.close()


	
