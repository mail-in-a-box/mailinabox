import base64, os, os.path

from flask import make_response

DEFAULT_KEY_PATH   = '/var/lib/mailinabox/api.key'
DEFAULT_AUTH_REALM = 'Mail-in-a-Box Management Server'

class KeyAuthService:
	"""Generate an API key for authenticating clients

	Clients must read the key from the key file and send the key with all HTTP
	requests. The key is passed as the username field in the standard HTTP
	Basic Auth header.
	"""
	def __init__(self, env):
		self.auth_realm = DEFAULT_AUTH_REALM
		self.key = self._generate_key()
		self.key_path = env.get('API_KEY_FILE') or DEFAULT_KEY_PATH

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

	def is_authenticated(self, request):
		"""Test if the client key passed in HTTP header matches the service key"""

		def decode(s):
			return base64.b64decode(s.encode('utf-8')).decode('ascii')

		def parse_api_key(header):
			if header is None:
				return

			scheme, credentials = header.split(maxsplit=1)
			if scheme != 'Basic':
				return

			username, password = decode(credentials).split(':', maxsplit=1)
			return username

		request_key = parse_api_key(request.headers.get('Authorization'))

		return request_key == self.key

	def make_unauthorized_response(self):
		return make_response(
			'You must pass the API key from "{0}" as the username\n'.format(self.key_path),
			401,
			{ 'WWW-Authenticate': 'Basic realm="{0}"'.format(self.auth_realm) })

	def _generate_key(self):
		raw_key = os.urandom(32)
		return base64.b64encode(raw_key).decode('ascii')
