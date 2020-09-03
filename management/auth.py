import base64, os, os.path, hmac

from flask import make_response

import utils, totp
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
		Returns a tuple of the user's email address and list of user privileges (e.g.
		('my@email', []) or ('my@email', ['admin']); raises a ValueError on login failure.
		If the user used an API key, the user's email is returned as None."""

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
			return (None, ["admin"])
		else:
			# The user is trying to log in with a username and user-specific
			# API key or password. Raises or returns privs and an indicator
			# whether the user is using their password or a user-specific API-key.
			privs, is_user_key = self.get_user_credentials(username, password, env)

			# If the user is using their API key to login, 2FA has been passed before
			if is_user_key:
				return (username, privs)

			totp_strategy = totp.TOTPStrategy(email=username)
			# this will raise `totp.MissingTokenError` or `totp.BadTokenError` for bad requests
			totp_strategy.validate_request(request, env)

			return (username, privs)

	def get_user_credentials(self, email, pw, env):
		# Validate a user's credentials. On success returns a list of
		# privileges (e.g. [] or ['admin']). On failure raises a ValueError
		# with a login error message.

		# Sanity check.
		if email == "" or pw == "":
			raise ValueError("Enter an email address and password.")

		is_user_key = False

		# The password might be a user-specific API key. create_user_key raises
		# a ValueError if the user does not exist.
		if hmac.compare_digest(self.create_user_key(email, env), pw):
			# OK.
			is_user_key = True
		else:
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

		# Get privileges for authorization. This call should never fail because by this
		# point we know the email address is a valid user. But on error the call will
		# return a tuple of an error message and an HTTP status code.
		privs = get_mail_user_privileges(email, env)
		if isinstance(privs, tuple): raise ValueError(privs[0])

		# Return a list of privileges.
		return (privs, is_user_key)

	def create_user_key(self, email, env):
		# Store an HMAC with the client. The hashed message of the HMAC will be the user's
		# email address & hashed password and the key will be the master API key. The user of
		# course has their own email address and password. We assume they do not have the master
		# API key (unless they are trusted anyway). The HMAC proves that they authenticated
		# with us in some other way to get the HMAC. Including the password means that when
		# a user's password is reset, the HMAC changes and they will correctly need to log
		# in to the control panel again. This method raises a ValueError if the user does
		# not exist, due to get_mail_password.
		msg = b"AUTH:" + email.encode("utf8") + b" " + get_mail_password(email, env).encode("utf8")
		return hmac.new(self.key.encode('ascii'), msg, digestmod="sha256").hexdigest()

	def _generate_key(self):
		raw_key = os.urandom(32)
		return base64.b64encode(raw_key).decode('ascii')
