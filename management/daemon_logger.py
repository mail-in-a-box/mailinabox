# -*- indent-tabs-mode: t; tab-width: 4; python-indent-offset: 4; -*-
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####

import logging
import flask

# setup our root logger

# keep a separate logger from app.logger, which only logs WARNING and
# above, doesn't include the module name, or authentication
# details

class textcolor:
	DANGER = '\033[31m'
	WARN = '\033[93m'
	SUCCESS = '\033[32m'
	BOLD = '\033[1m'
	FADED= '\033[37m'
	RESET = '\033[0m'



class AuthLogFormatter(logging.Formatter):
	def __init__(self):
		fmt='%(name)s:%(lineno)d(%(username)s/%(client)s): %(levelname)s[%(thread)d]: %(color)s%(message)s%(color_reset)s'
		super(AuthLogFormatter, self).__init__(fmt=fmt)


#
# when logging, a "client" (oauth client) and/or an explicit
# "username" (in the case the user in question is not logged in but
# you want the username to appear in the logs) may be provided in the
# log.xxx() call as the last argument. eg:
#
# log.warning('login attempt failed', { 'username': email })
#

class AuthLogFilter(logging.Filter):
	def __init__(self, color_output, get_session_username_function):
		self.color_output = color_output
		self.get_session_username = get_session_username_function
		super(AuthLogFilter, self).__init__()
	
	''' add `username` and `client` context info the the LogRecord '''
	def filter(self, record):
		record.color = ''
		if self.color_output:
			if record.levelno == logging.DEBUG:
				record.color=textcolor.FADED
			elif record.levelno == logging.INFO:
				record.color=textcolor.BOLD
			elif record.levelno == logging.WARNING:
				record.color=textcolor.WARN
			elif record.levelno in [logging.ERROR, logging.CRITICAL]:
				record.color=textcolor.DANGER
				
		record.color_reset = textcolor.RESET if record.color else ''
		record.client = '-'
		record.username = '-'
		record.thread = record.thread % 10000

		opts = None
		args_len = len(record.args)
		if type(record.args) == dict:
			opts = record.args
			record.args = ()
		elif args_len>0 and type(record.args[args_len-1]) == dict:
			opts = record.args[args_len-1]
			record.args = record.args[0:args_len-1]

		if opts:
			record.client = opts.get('client', '-')
			record.username = opts.get('username', '-')

		if record.username == '-':
			try:
				record.username = self.get_session_username()
			except (RuntimeError, KeyError):
				# not in an HTTP request context or not logged in
				pass

		return True

def get_session_username():
	if flask.request and hasattr(flask.request, 'user_email'):
		# this is an admin panel login via "authorized_personnel_only"
		return flask.request.user_email

	# otherwise, this may be a user session login
	return flask.session['user_id']
	

def add_python_logging(app):
	# log to stdout in development mode
	if app.debug:
		log_level = logging.DEBUG
		log_handler = logging.StreamHandler()
		logging.basicConfig(level=log_level, handlers=[])
		log_handler.setLevel(log_level)
		log_handler.addFilter(AuthLogFilter(
			app.debug,
			get_session_username
		))
		log_handler.setFormatter(AuthLogFormatter())
		log = logging.getLogger('')
		log.addHandler(log_handler)

	# hook python log to gunicorn in production mode
	else:
		gunicorn_logger = logging.getLogger('gunicorn.error')
		log = logging.getLogger('')
		log.handlers = gunicorn_logger.handlers
		log.setLevel(gunicorn_logger.level)

		
