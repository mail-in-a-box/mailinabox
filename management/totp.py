import base64
import hmac
import io
import os
import struct
import time
import pyotp
import qrcode

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
	return totp.verify(token, valid_window=2)
