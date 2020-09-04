import base64
import hmac
import io
import os
import struct
import time
import pyotp
import qrcode
from mailconfig import get_mfa_state, set_mru_totp_code

def get_secret():
	return base64.b32encode(os.urandom(20)).decode('utf-8')

def get_otp_uri(secret, email):
	return pyotp.TOTP(secret).provisioning_uri(
		name=email,
		issuer_name='mailinabox'
	)

def get_qr_code(data):
	qr = qrcode.make(data)
	byte_arr = io.BytesIO()
	qr.save(byte_arr, format='PNG')

	encoded = base64.b64encode(byte_arr.getvalue()).decode('utf-8')
	return 'data:image/png;base64,{}'.format(encoded)

def validate(secret, token):
	"""
	@see https://tools.ietf.org/html/rfc6238#section-4
	@see https://tools.ietf.org/html/rfc4226#section-5.4
	"""
	totp = pyotp.TOTP(secret)
	return totp.verify(token, valid_window=1)

class MissingTokenError(ValueError):
	pass

class BadTokenError(ValueError):
	pass

class TOTPStrategy():
	def __init__(self, email):
		self.type = 'totp'
		self.email = email

	def store_successful_login(self, token, env):
		return set_mru_totp_code(self.email, token, env)

	def validate_request(self, request, env):
		mfa_state = get_mfa_state(self.email, env)

		# 2FA is not enabled, we can skip further checks
		if mfa_state['type'] != 'totp':
			return True

		# If 2FA is enabled, raise if:
		# 1. no token is provided via `x-auth-token`
		# 2. a previously supplied token is used (to counter replay attacks)
		# 3. the token is invalid
		# in that case, we need to raise and indicate to the client to supply a TOTP
		token_header = request.headers.get('x-auth-token')

		if not token_header:
			raise MissingTokenError("Two factor code missing (no x-auth-token supplied)")

		# TODO: Should a token replay be handled as its own error?
		if token_header == mfa_state['mru_token'] or validate(mfa_state['secret'], token_header) != True:
			raise BadTokenError("Two factor code incorrect")

		self.store_successful_login(token_header, env)
		return True
