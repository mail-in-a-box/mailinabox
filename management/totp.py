import base64
import hmac
import io
import os
import struct
import time
from urllib.parse import quote
import qrcode

def get_secret():
	return base64.b32encode(os.urandom(20)).decode('utf-8')

def get_otp_uri(secret, email):
	site_name = 'mailinabox'

	return 'otpauth://totp/{}:{}?secret={}&issuer={}'.format(
		quote(site_name),
		quote(email),
		secret,
		quote(site_name)
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
	@see https://git.sr.ht/~sircmpwn/meta.sr.ht/tree/master/metasrht/totp.py
	@see https://github.com/susam/mintotp/blob/master/mintotp.py
	TODO: resynchronisation
	"""
	key = base64.b32decode(secret)
	tm = int(time.time() / 30)
	digits = 6

	step = 0
	counter = struct.pack('>Q', tm + step)

	hm = hmac.HMAC(key, counter, 'sha1').digest()
	offset = hm[-1] &0x0F
	binary = struct.unpack(">L", hm[offset:offset + 4])[0] & 0x7fffffff

	code = str(binary)[-digits:].rjust(digits, '0')
	return token == code
