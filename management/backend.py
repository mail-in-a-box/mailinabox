#!/usr/local/lib/mailinabox/env/bin/python
# -*- indent-tabs-mode: t; tab-width: 4; python-indent-offset: 4; -*-

import ldap3, time


class Response:
	#
	# helper class for iterating over ldap search results
	# example:
	#    conn = connect()
	#    response = conn.wait( conn.search(...) )
	#    for record in response:
	#        print(record['dn'])
	#
	rowidx=0
	def __init__(self, result, response):
		self.result = result
		self.response = response
		if result is None:
			raise ValueError("INVALID RESULT: None")
		
	def __iter__(self):
		self.rowidx=0
		return self
	
	def __next__(self):
		# return the next record in the result set
		rtn = self.next()
		if rtn is None:	raise StopIteration
		return rtn
	
	def next(self):
		# return the next record in the result set or None
		if self.rowidx >= len(self.response):
			return None
		rtn=self.response[self.rowidx]['attributes']
		rtn['dn'] = self.response[self.rowidx]['dn']
		self.rowidx += 1
		
		return rtn
	
	def count(self):
		# return the number of records in the result set
		return len(self.response)
		


class PagedSearch:
	#
	# Helper class for iterating over and handling paged searches.
	# Use PagedSearch when expecting a large number of matching
	# entries. slapd by default limits each result set to 500 entries.
	#
	# example:
	#  conn=connection()
	#  response = conn.paged_search(...)
	#  for record in response:
	#     print(record['dn'])
	#
	# PagedSearch is limited to one iteration pass. In the above
	# example the 'for' statement could not be repeated.
	#

	def __init__(self, conn, search_base, search_filter, search_scope, attributes, page_size):
		self.conn = conn
		self.search_base = search_base
		self.search_filter = search_filter
		self.search_scope = search_scope
		self.attributes = attributes
		self.page_size = page_size

		# issue the search
		self.response = None
		self.id = conn.search(search_base, search_filter, search_scope, attributes=attributes, paged_size=page_size, paged_criticality=True)
		self.page_count = 0
		
	def __iter__(self):
		# wait for the search result on first iteration
		self.response = self.conn.wait(self.id)
		self.page_count += 1
		return self

	def __next__(self):
		# return the next record in the result set
		r = self.response.next()
		if r is None:
			cookie=self.response.result['controls']['1.2.840.113556.1.4.319']['value']['cookie']
			if not cookie:
				raise StopIteration
			self.id = self.conn.search(self.search_base, self.search_filter, self.search_scope, attributes=self.attributes, paged_size=self.page_size, paged_cookie=cookie)
			self.response = self.conn.wait(self.id)
			self.page_count += 1
			r = self.response.next()
			if r is None:
				raise StopIteration
		return r

	def abandon(self):
		# "If you send 0 as paged_size and a valid cookie the search
		# operation referred by that cookie is abandoned."
		cookie=self.response.result['controls']['1.2.840.113556.1.4.319']['value']['cookie']
		if not cookie: return
		self.id = self.conn.search(self.search_base, self.search_filter, self.search_scope, attributes=self.attributes, paged_size=0, paged_cookie=cookie)
		



class LdapConnection(ldap3.Connection):
	# This is a subclass ldap3.Connection with our own methods for
	# simplifying searches and modifications
	
	def wait(self, id):
		# Wait for results from an async search and return the result
		# set in a Response object.  If a syncronous strategy is in
		# use, it returns immediately with the Response object.
		if type(id)==int:
			# async
			tup = self.get_response(id)
			return Response(tup[1], tup[0])
		else:
			# sync - conn has returned results
			return Response(self.result, self.response)

	def paged_search(self, search_base, search_filter, search_scope=ldap3.SUBTREE, attributes=None, page_size=200):
		# Perform a paged search - see PagedSearch above
		return PagedSearch(self,
				   search_base,
				   search_filter,
				   search_scope,
				   attributes,
				   page_size)

	def add(self, dn, object_class=None, attrs=None, controls=None):
		# This overrides ldap3's add method to automatically remove
		# empty attributes from the attribute list for a ldap ADD
		# operation, which cause exceptions.
		if attrs is not None:
			keys = [ k for k in attrs ]
			for k in keys:
				if attrs[k] is None or \
				   type(attrs[k]) is list and len(attrs[k])==0 or \
				   type(attrs[k]) is str and attrs[k]=='':
					del attrs[k]
		return ldap3.Connection.add(self, dn, object_class, attrs, controls)

	def chase_members(self, members, attrib, env):
		# Given a list of distinguished names (members), lookup each
		# one and return the list of values for `attrib` in an
		# array. It is *not* recursive. `attrib` is a string holding
		# the name of an attribute.
		resolved=[]
		for dn in members:
			try:
				response = self.wait(self.search(dn, "(objectClass=*)", ldap3.BASE, attributes=attrib))
				rec = response.next()
				if rec is not None: resolved.append(rec[attrib])
			except ldap3.core.exceptions.LDAPNoSuchObjectResult:
				# ignore orphans
				pass
		return resolved

	# static
	def ldap_modify_op(attr, record, new_values):
		# Return an ldap operation to change record[attr] so that it
		# has values `new_values`. `new_values` is a list.
		
		if not type(new_values) is list:
			new_values = [ new_values ]
		# remove None values
		new_values = [ v for v in new_values if v is not None ]

		if len(record[attr]) == 0:
			if len(new_values) == 0:
				# NOP: current=empty, desired=empty
				return None
			# ADD: current=empty, desired=non-empty
			return [(ldap3.MODIFY_ADD, new_values)]
		if len(new_values) == 0:
			# DELETE: current=non-empty, desired=empty
			return [(ldap3.MODIFY_DELETE, [])]
		# MODIFY: current=non-empty, desired=non-empty
		return [(ldap3.MODIFY_REPLACE, new_values)]



	def add_or_modify(self, dn, existing_record, attrs_to_update, objectClasses, values):
		# Add or modify an existing database entry.
		#   dn: dn for a new entry
		#   existing_record: the existing data, if any
		#         (a dict from Response.next()). The data must
		#         have values for each attribute in `attrs_to_update`
		#   attrs_to_update: an array of attribute names to update
		#   objectClasses: a list of object classes for a new entry
		#   values: a dict of attributes and values for a new entry
		if existing_record:
			# modify existing
			changes = {}
			dn = existing_record['dn']
			for attr in attrs_to_update:
				modify_op = LdapConnection.ldap_modify_op(
					attr,
					existing_record,
					values[attr])
				if modify_op: changes[attr] = modify_op
			self.wait ( self.modify(dn, changes) )
			return 'modify'
		else:
			# add new alias
			self.wait ( self.add(dn, objectClasses, values) )
			return 'add'

		
	def modify_record(self, rec, modifications):
		# Modify an existing record by changing the attributes of
		# `modifications` to their associated values. `modifications`
		# is a dict with key of attribute name and value of list of
		# string.
		dn = rec['dn']
		attrs_to_update=modifications.keys()
		self.add_or_modify(dn, rec, attrs_to_update, None, modifications)
		return True
	

def get_shadowLastChanged():
	# get the number of days from the epoch
	days = int(time.time() / (24 * 60 * 60))
	return days


def get_ldap_server(env):
	# return a ldap3.Server object for a ldap connection
	tls=None
	if env.LDAP_SERVER_TLS=="yes":
		import ssl
		tls=ldap3.Tls(
			validate=ssl.CERT_REQUIRED,
			ca_certs_file="/etc/ssl/certs/ca-certificates.crt")

	server=ldap3.Server(
		host=env.LDAP_SERVER,
		port=int(env.LDAP_SERVER_PORT),
		use_ssl=False if tls is None else True,
		get_info=ldap3.NONE,
		tls=tls)
	
	return server


def connect(env):
	# connect to the ldap server
	#
	# problems and observations:
	#
	# using thread-local storage does not work with Flask.  nor does
	# REUSABLE strategy - both fail with LDAPResponseTimeoutError
	#
	# there are a lot of connections left open with ASYNC strategy
	#
	# there are more unclosed connections with manual bind vs auto
	# bind
	#
	# pooled connections only work for REUSABLE strategy
	#
	# paging does not work with REUSABLE strategy at all:
	# get_response() always returns a protocol error (invalid cookie)
	# when retrieving the second page
	#
	server = get_ldap_server(env)

	auto_bind=ldap3.AUTO_BIND_NO_TLS
	if env.LDAP_SERVER_STARTTLS=="yes":
		auto_bind=ldap3.AUTO_BIND_TLS_BEFORE_BIND
		
	conn = LdapConnection(
		server,
		env.LDAP_MANAGEMENT_DN,
		env.LDAP_MANAGEMENT_PASSWORD,
		auto_bind=auto_bind,
		lazy=False,
		#client_strategy=ldap3.ASYNC, # ldap3.REUSABLE,
		client_strategy=ldap3.SYNC,
		#pool_name="default",
		#pool_size=5,
		#pool_lifetime=20*60,  # 20 minutes
		#pool_keepalive=60,
		raise_exceptions=True)
	
	#conn.bind()
	return conn




