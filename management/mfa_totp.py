# -*- indent-tabs-mode: t; tab-width: 4; python-indent-offset: 4; -*-
import base64
import hmac
import pyotp
import qrcode
import io
import os
import time

from mailconfig import open_database

def id_from_index(user, index):
	'''return a unique id for the user's totp entry. the index itself
	should be avoided to ensure a change in the order does not cause
	an unexpected change.

	'''
	return 'totp:' + user['totpMruTokenTime'][index]

def index_from_id(user, id):
	'''return the index of the corresponding id from the list of totp
	entries for a user, or -1 if not found

	'''
	for index in range(0, len(user['totpSecret'])):
		xid = id_from_index(user, index)
		if xid == id:
			return index
	return -1

def time_ns():
	if "time_ns" in dir(time):
		return time.time_ns()
	else:
		return int(time.time() * 1000000000)
	
def get_state(user):
	state_list = []

	# totp
	for idx in range(0, len(user['totpSecret'])):
		state_list.append({
			'id': id_from_index(user, idx),
			'type': 'totp',
			'secret': user['totpSecret'][idx],
			'mru_token': user['totpMruToken'][idx],
			'label': user['totpLabel'][idx]
		})
	return state_list

def enable(user, secret, token, label, env):
	validate_secret(secret)
	# Sanity check with the provide current token.
	totp = pyotp.TOTP(secret)
	if not totp.verify(token, valid_window=1):
		raise ValueError("Invalid token.")

	mods = {
		"totpSecret": user['totpSecret'].copy() + [secret],
		"totpMruToken": user['totpMruToken'].copy() + [''],
		"totpMruTokenTime": user['totpMruTokenTime'].copy() + [time_ns()],
		"totpLabel": user['totpLabel'].copy() + [label or '']
	}
	if 'totpUser' not in user['objectClass']:
		 mods['objectClass'] = user['objectClass'].copy() + ['totpUser']
	
	conn = open_database(env)
	conn.modify_record(user, mods)

def set_mru_token(user, id, token, env):
	# return quietly if the user is not configured for TOTP
	if 'totpUser' not in user['objectClass']: return

	# ensure the id is valid
	idx = index_from_id(user, id)
	if idx<0:
		raise ValueError('MFA/totp mru index is out of range')

	# store the token
	mods = {
		"totpMruToken": user['totpMruToken'].copy(),
		"totpMruTokenTime": user['totpMruTokenTime'].copy()
	}
	mods['totpMruToken'][idx] = token
	mods['totpMruTokenTime'][idx] = time_ns()
	conn = open_database(env)
	conn.modify_record(user, mods)


def disable(user, id, env):
	# Disable a particular MFA mode for a user.
	if id is None:
		# Disable all totp
		mods = {
			"objectClass": user["objectClass"].copy(),
			"totpMruToken": None,
			"totpMruTokenTime": None,
			"totpSecret": None,
			"totpLabel": None
		}
		mods["objectClass"].remove("totpUser")	
		open_database(env).modify_record(user, mods)
		return True

	else:
		# Disable totp at the index specified
		idx = index_from_id(user, id)	
		if idx<0 or idx>=len(user['totpSecret']):
			return False
		mods = {
			"objectClass": user["objectClass"].copy(),
			"totpMruToken": user["totpMruToken"].copy(),
			"totpMruTokenTime": user["totpMruTokenTime"].copy(),
			"totpSecret": user["totpSecret"].copy(),
			"totpLabel": user["totpLabel"].copy()
		}
		mods["totpMruToken"].pop(idx)
		mods["totpMruTokenTime"].pop(idx)
		mods["totpSecret"].pop(idx)
		mods["totpLabel"].pop(idx)
		if len(mods["totpSecret"])==0:
			mods['objectClass'].remove('totpUser')
		open_database(env).modify_record(user, mods)
		return True


def validate_secret(secret):
	if type(secret) != str or secret.strip() == "":
		raise ValueError("No secret provided.")
	if len(secret) != 32:
		raise ValueError("Secret should be a 32 characters base32 string")

def provision(email, env):
	# Make a new secret.
	secret = base64.b32encode(os.urandom(20)).decode('utf-8')
	validate_secret(secret) # sanity check

	# Make a URI that we encode within a QR code.
	uri = pyotp.TOTP(secret).provisioning_uri(
		name=email,
		issuer_name=env["PRIMARY_HOSTNAME"] + " Mail-in-a-Box Control Panel"
	)

	# Generate a QR code as a base64-encode PNG image.
	qr = qrcode.make(uri)
	byte_arr = io.BytesIO()
	qr.save(byte_arr, format='PNG')
	png_b64 = base64.b64encode(byte_arr.getvalue()).decode('utf-8')

	return {
		"type": "totp",
		"secret": secret,
		"qr_code_base64": png_b64
	}


def validate_auth(user, state, request, save_mru, env):
	# Check that a token is present in the X-Auth-Token header.
	# If not, give a hint that one can be supplied.
	token = request.headers.get('x-auth-token')
	if not token:
		return (False, "missing-totp-token")

	# Check for a replay attack.
	if hmac.compare_digest(token, state['mru_token'] or ""):
		# If the token fails, skip this MFA mode.
		return (False, "invalid-totp-token")

	# Check the token.
	totp = pyotp.TOTP(state["secret"])
	if not totp.verify(token, valid_window=1):
		return (False, "invalid-totp-token")

	# On success, record the token to prevent a replay attack.
	if save_mru:
		set_mru_token(user, state['id'], token, env)

	return (True, None)
