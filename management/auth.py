import base64, os, os.path, hmac, json, secrets

from expiringdict import ExpiringDict

import utils
from mailconfig import get_mail_password, get_mail_user_privileges
from mfa import get_hash_mfa_state, validate_auth_mfa

DEFAULT_KEY_PATH   = '/var/lib/mailinabox/api.key'
DEFAULT_AUTH_REALM = 'Mail-in-a-Box Management Server'

class KeyAuthService:
	"""Generate an API key for authenticating clients

	Clients must read the key from the key file and send the key with all HTTP
	requests. The key is passed as the username field in the standard HTTP
	Basic Auth header.
	"""
	__token_dict = ExpiringDict(max_len=1024, max_age_seconds=600)

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
			# The user passed the master API key which grants administrative privs.
			return (None, ["admin"], None)
		else:
			# The user is trying to log in with a username and either a password
			# (and possibly a MFA token) or a user-specific API key.
			token = None
			privs = self.check_user_auth(username, password, request, env)
			if not self.validate_user_token(username, request, env):
				token = secrets.token_hex(16)
				KeyAuthService.__token_dict[username] = token
			return (username, privs, token)

	def check_user_auth(self, email, pw, request, env):
		# Validate a user's login email address and password. If MFA is enabled,
		# check the MFA token in the X-Auth-Token header.
		#
		# On success returns a list of privileges (e.g. [] or ['admin']). On login
		# failure, raises a ValueError with a login error message.

		# Sanity check.
		if email == "" or pw == "":
			raise ValueError("Enter an email address and password.")

		# The password might be a user-specific API key. create_user_key raises
		# a ValueError if the user does not exist.
		if hmac.compare_digest(self.create_user_key(email, env), pw):
			# OK.
			pass
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

			# If MFA is enabled, check that MFA passes.
			status, hints = validate_auth_mfa(email, request, env)
			if not status:
				# Login valid. Hints may have more info.
				raise ValueError(",".join(hints))

		# Get privileges for authorization. This call should never fail because by this
		# point we know the email address is a valid user. But on error the call will
		# return a tuple of an error message and an HTTP status code.
		privs = get_mail_user_privileges(email, env)
		if isinstance(privs, tuple): raise ValueError(privs[0])

		# Return a list of privileges.
		return privs

	def check_user_token(self, email, token, request, env):
		# Check whether a token matches the one we stored for the user.
		return token is not None and KeyAuthService.__token_dict.get(email) == token

	def validate_user_token(self, email, request, env):
		# Check whether the provided token in request cookie matches the one we stored for the user.
		return self.check_user_token(email, request.cookies.get("miab-cp-token"), request, env)

	def remove_user_token(self, email, request, env):
		# Remove the user's token from the in-memory session database.
		# Returns the invalidated token if exists.
		return KeyAuthService.__token_dict.pop(email)

	def create_user_key(self, email, env):
		# Create a user API key, which is a shared secret that we can re-generate from
		# static information in our database. The shared secret contains the user's
		# email address, current hashed password, and current MFA state, so that the
		# key becomes invalid if any of that information changes.
		#
		# Use an HMAC to generate the API key using our master API key as a key,
		# which also means that the API key becomes invalid when our master API key
		# changes --- i.e. when this process is restarted.
		#
		# Raises ValueError via get_mail_password if the user doesn't exist.

		# Construct the HMAC message from the user's email address and current password.
		msg = b"AUTH:" + email.encode("utf8") + b" " + get_mail_password(email, env).encode("utf8")

		# Add to the message the current MFA state, which is a list of MFA information.
		# Turn it into a string stably.
		msg += b" " + json.dumps(get_hash_mfa_state(email, env), sort_keys=True).encode("utf8")

		# Make the HMAC.
		hash_key = self.key.encode('ascii')
		return hmac.new(hash_key, msg, digestmod="sha256").hexdigest()

	def _generate_key(self):
		raw_key = os.urandom(32)
		return base64.b64encode(raw_key).decode('ascii')
