import base64, os, os.path

from flask import make_response

import utils
from mailconfig import get_mail_password, get_mail_user_privileges

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

	def authenticate(self, request, env):
		"""Test if the client key passed in HTTP Authorization header matches the service key
		or if the or username/password passed in the header matches an administrator user.
		Returns a list of user privileges (e.g. [] or ['admin']) raise a ValueError on
		login failure."""

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
			raise ValueError("No authorization header provided.")

		username, password = parse_basic_auth(header)

		if username in (None, ""):
			raise ValueError("Authorization header invalid.")
		elif username == self.key:
			# The user passed the API key which grants administrative privs.
			return ["admin"]
		else:
			# The user is trying to log in with a username and password.
			# Raises or returns privs.
			return self.get_user_credentials(username, password, env)

	def get_user_credentials(self, email, pw, env):
		# Validate a user's credentials. On success returns a list of
		# privileges (e.g. [] or ['admin']). On failure raises a ValueError
		# with a login error message. 

		# Sanity check.
		if email == "" or pw == "":
			raise ValueError("Enter an email address and password.")

		# Get the hashed password of the user. Raise a ValueError if the
		# email address does not correspond to a user.
		pw_hash = get_mail_password(email, env)

		# Authenticate.
		try:
			# Use 'doveadm pw' to check credentials. doveadm will return
			# a non-zero exit status if the credentials are no good,
			# and check_call will raise an exception in that case.
			utils.shell('check_call', [
				"/usr/bin/doveadm", "pw",
				"-p", pw,
				"-t", pw_hash,
				])
		except:
			# Login failed.
			raise ValueError("Invalid password.")

		# Get privileges for authorization.

		# (This call should never fail on a valid user. But if it did fail, it would
		# return a tuple of an error message and an HTTP status code.)
		privs = get_mail_user_privileges(email, env)
		if isinstance(privs, tuple): raise Exception("Error getting privileges.")

		# Return a list of privileges.
		return privs

	def _generate_key(self):
		raw_key = os.urandom(32)
		return base64.b64encode(raw_key).decode('ascii')
