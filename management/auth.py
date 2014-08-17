import base64, os, os.path

from flask import make_response

import utils
from mailconfig import get_mail_user_privileges

DEFAULT_KEY_PATH   = '/var/lib/mailinabox/api.key'
DEFAULT_AUTH_REALM = 'Mail-in-a-Box Management Server'

class KeyAuthService:
	"""Generate an API key for authenticating clients

	Clients must read the key from the key file and send the key with all HTTP
	requests. The key is passed as the username field in the standard HTTP
	Basic Auth header.
	"""
	def __init__(self):
		self.auth_realm = DEFAULT_AUTH_REALM
		self.key = self._generate_key()
		self.key_path = DEFAULT_KEY_PATH

	def write_key(self):
		"""Write key to file so authorized clients can get the key

		The key file is created with mode 0640 so that additional users can be
		authorized to access the API by granting group/ACL read permissions on
		the key file.
		"""
		def create_file_with_mode(path, mode):
			# Based on answer by A-B-B: http://stackoverflow.com/a/15015748
			old_umask = os.umask(0)
			try:
				return os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT, mode), 'w')
			finally:
				os.umask(old_umask)

		os.makedirs(os.path.dirname(self.key_path), exist_ok=True)

		with create_file_with_mode(self.key_path, 0o640) as key_file:
			key_file.write(self.key + '\n')

	def is_authenticated(self, request, env):
		"""Test if the client key passed in HTTP Authorization header matches the service key
		or if the or username/password passed in the header matches an administrator user.
		Returns 'OK' if the key is good or the user is an administrator, otherwise an error message."""

		def decode(s):
			return base64.b64decode(s.encode('ascii')).decode('ascii')

		def parse_basic_auth(header):
			if " " not in header:
				return None, None
			scheme, credentials = header.split(maxsplit=1)
			if scheme != 'Basic':
				return None, None

			credentials = decode(credentials)
			if ":" not in credentials:
				return None, None
			username, password = credentials.split(':', maxsplit=1)
			return username, password

		header = request.headers.get('Authorization')
		if not header:
			return "No authorization header provided."

		username, password = parse_basic_auth(header)

		if username in (None, ""):
			return "Authorization header invalid."
		elif username == self.key:
			return "OK"
		else:
			return self.check_imap_login( username, password, env)

	def check_imap_login(self, email, pw, env):
		# Validate a user's credentials.

		# Sanity check.
		if email == "" or pw == "":
			return "Enter an email address and password."

		# Authenticate.
		try:
			# Use doveadm to check credentials. doveadm will return
			# a non-zero exit status if the credentials are no good,
			# and check_call will raise an exception in that case.
			utils.shell('check_call', [
				"/usr/bin/doveadm",
				"auth", "test",
				email, pw
				])
		except:
			# Login failed.
			return "Invalid email address or password."

		# Authorize.
		# (This call should never fail on a valid user.)
		privs = get_mail_user_privileges(email, env)
		if isinstance(privs, tuple): raise Exception("Error getting privileges.")
		if "admin" not in privs:
			return "You are not an administrator for this system."

		return "OK"

	def _generate_key(self):
		raw_key = os.urandom(32)
		return base64.b64encode(raw_key).decode('ascii')
