import base64, os, os.path, hmac, json, secrets
from datetime import timedelta

from expiringdict import ExpiringDict

import utils
from mailconfig import get_mail_password, get_mail_user_privileges
from mfa import get_hash_mfa_state, validate_auth_mfa

DEFAULT_KEY_PATH   = '/var/lib/mailinabox/api.key'
DEFAULT_AUTH_REALM = 'Mail-in-a-Box Management Server'

class AuthService:
	def __init__(self):
		self.auth_realm = DEFAULT_AUTH_REALM
		self.key_path = DEFAULT_KEY_PATH
		self.max_session_duration = timedelta(days=2)

		self.init_system_api_key()
		self.sessions = ExpiringDict(max_len=64, max_age_seconds=self.max_session_duration.total_seconds())

	def init_system_api_key(self):
		"""Write an API key to a local file so local processes can use the API"""

		def create_file_with_mode(path, mode):
			# Based on answer by A-B-B: http://stackoverflow.com/a/15015748
			old_umask = os.umask(0)
			try:
				return os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT, mode), 'w')
			finally:
				os.umask(old_umask)

		self.key = secrets.token_hex(32)

		os.makedirs(os.path.dirname(self.key_path), exist_ok=True)

		with create_file_with_mode(self.key_path, 0o640) as key_file:
			key_file.write(self.key + '\n')

	def authenticate(self, request, env, login_only=False, logout=False):
		"""Test if the HTTP Authorization header's username matches the system key, a session key,
		or if the username/password passed in the header matches a local user.
		Returns a tuple of the user's email address and list of user privileges (e.g.
		('my@email', []) or ('my@email', ['admin']); raises a ValueError on login failure.
		If the user used the system API key, the user's email is returned as None since
		this key is not associated with a user."""

		def parse_http_authorization_basic(header):
			def decode(s):
				return base64.b64decode(s.encode('ascii')).decode('ascii')
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

		username, password = parse_http_authorization_basic(request.headers.get('Authorization', ''))
		if username in (None, ""):
			raise ValueError("Authorization header invalid.")

		if username.strip() == "" and password.strip() == "":
			raise ValueError("No email address, password, session key, or API key provided.")

		# If user passed the system API key, grant administrative privs. This key
		# is not associated with a user.
		if username == self.key and not login_only:
			return (None, ["admin"])

		# If the password corresponds with a session token for the user, grant access for that user.
		if self.get_session(username, password, "login", env) and not login_only:
			sessionid = password
			session = self.sessions[sessionid]
			if logout:
				# Clear the session.
				del self.sessions[sessionid]
			else:
				# Re-up the session so that it does not expire.
				self.sessions[sessionid] = session

		# If no password was given, but a username was given, we're missing some information.
		elif password.strip() == "":
			raise ValueError("Enter a password.")

		else:
			# The user is trying to log in with a username and a password
			# (and possibly a MFA token). On failure, an exception is raised.
			self.check_user_auth(username, password, request, env)

		# Get privileges for authorization. This call should never fail because by this
		# point we know the email address is a valid user --- unless the user has been
		# deleted after the session was granted. On error the call will return a tuple
		# of an error message and an HTTP status code.
		privs = get_mail_user_privileges(username, env)
		if isinstance(privs, tuple): raise ValueError(privs[0])

		# Return the authorization information.
		return (username, privs)

	def check_user_auth(self, email, pw, request, env):
		# Validate a user's login email address and password. If MFA is enabled,
		# check the MFA token in the X-Auth-Token header.
		#
		# On login failure, raises a ValueError with a login error message. On
		# success, nothing is returned.

		# Authenticate.
		try:
			# Get the hashed password of the user. Raise a ValueError if the
			# email address does not correspond to a user. But wrap it in the
			# same exception as if a password fails so we don't easily reveal
			# if an email address is valid.
			pw_hash = get_mail_password(email, env)

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
			raise ValueError("Incorrect email address or password.")

		# If MFA is enabled, check that MFA passes.
		status, hints = validate_auth_mfa(email, request, env)
		if not status:
			# Login valid. Hints may have more info.
			raise ValueError(",".join(hints))

	def create_user_password_state_token(self, email, env):
		# Create a token that changes if the user's password or MFA options change
		# so that sessions become invalid if any of that information changes.
		msg = get_mail_password(email, env).encode("utf8")

		# Add to the message the current MFA state, which is a list of MFA information.
		# Turn it into a string stably.
		msg += b" " + json.dumps(get_hash_mfa_state(email, env), sort_keys=True).encode("utf8")

		# Make a HMAC using the system API key as a hash key.
		hash_key = self.key.encode('ascii')
		return hmac.new(hash_key, msg, digestmod="sha256").hexdigest()

	def create_session_key(self, username, env, type=None):
		# Create a new session.
		token = secrets.token_hex(32)
		self.sessions[token] = {
			"email": username,
			"password_token": self.create_user_password_state_token(username, env),
			"type": type,
		}
		return token

	def get_session(self, user_email, session_key, session_type, env):
		if session_key not in self.sessions: return None
		session = self.sessions[session_key]
		if session_type == "login" and session["email"] != user_email: return None
		if session["type"] != session_type: return None
		if session["password_token"] != self.create_user_password_state_token(session["email"], env): return None
		return session
