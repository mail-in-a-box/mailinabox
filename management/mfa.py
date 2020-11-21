import base64
import hmac
import io
import json
import os
import pyotp
import qrcode
import pywarp
import pywarp.backends

from mailconfig import open_database

def get_user_id(email, c):
	c.execute('SELECT id FROM users WHERE email=?', (email,))
	r = c.fetchone()
	if not r: raise ValueError("User does not exist.")
	return r[0]

def get_mfa_state(email, env):
	c = open_database(env)
	c.execute('SELECT id, type, secret, mru_token, label FROM mfa WHERE user_id=?', (get_user_id(email, c),))
	return [
		{ "id": r[0], "type": r[1], "secret": r[2], "mru_token": r[3], "label": r[4] }
		for r in c.fetchall()
	]

def get_public_mfa_state(email, env):
	mfa_state = get_mfa_state(email, env)
	return [
		{ "id": s["id"], "type": s["type"], "label": s["label"] }
		for s in mfa_state
	]

def get_hash_mfa_state(email, env):
	# Get the current MFA credential secrets from which we form a hash
	# so that we can reset user logins when any authentication information
	# changes.
	mfa_state = []
	for s in get_mfa_state(email, env):
		# Add TOTP id and secret to the state.
		# Skip WebAuthn state if it's just a challenge.
		if s["type"] == "webauthn":
			try:
				# Get the credential and only include it (not challenges) in the state.
				s["secret"] = json.loads(s["secret"])["cred_pub_key"]
			except:
				# Skip this one --- there is no cred_pub_key.
				continue
		mfa_state.append({ "id": s["id"], "type": s["type"], "secret": s["secret"] })
	return mfa_state

def enable_mfa(email, type, env, *args):
	if type == "totp":
		secret, token, label = args
		validate_totp_secret(secret)
		# Sanity check with the provide current token.
		totp = pyotp.TOTP(secret)
		if not totp.verify(token, valid_window=1):
			raise ValueError("Invalid token.")
		conn, c = open_database(env, with_connection=True)
		c.execute('INSERT INTO mfa (user_id, type, secret, label) VALUES (?, ?, ?, ?)', (get_user_id(email, c), type, secret, label))
		conn.commit()
	elif type == "webauthn":
		attestationObject, clientDataJSON = args
		rp = pywarp.RelyingPartyManager(
			get_relying_party_name(env),
			rp_id=env["PRIMARY_HOSTNAME"], # must match hostname the control panel is served from
			credential_storage_backend=WebauthnStorageBackend(env))
		rp.register(attestation_object=base64.b64decode(attestationObject), client_data_json=base64.b64decode(clientDataJSON), email=email.encode("utf8")) # encoding of email is a little funky here, pywarp calls .decode() with no args?
	else:
		raise ValueError("Invalid MFA type.")


def set_mru_token(email, mfa_id, token, env):
	conn, c = open_database(env, with_connection=True)
	c.execute('UPDATE mfa SET mru_token=? WHERE user_id=? AND id=?', (token, get_user_id(email, c), mfa_id))
	conn.commit()

def disable_mfa(email, mfa_id, env):
	conn, c = open_database(env, with_connection=True)
	if mfa_id is None:
		# Disable all MFA for a user.
		c.execute('DELETE FROM mfa WHERE user_id=?', (get_user_id(email, c),))
	else:
		# Disable a particular MFA mode for a user.
		c.execute('DELETE FROM mfa WHERE user_id=? AND id=?', (get_user_id(email, c), mfa_id))
	conn.commit()
	return c.rowcount > 0

def validate_totp_secret(secret):
	if type(secret) != str or secret.strip() == "":
		raise ValueError("No secret provided.")
	if len(secret) != 32:
		raise ValueError("Secret should be a 32 characters base32 string")

def get_relying_party_name(env):
	return env["PRIMARY_HOSTNAME"] + " Mail-in-a-Box Control Panel"

def provision_totp(email, env):
	# Make a new secret.
	secret = base64.b32encode(os.urandom(20)).decode('utf-8')
	validate_totp_secret(secret) # sanity check

	# Make a URI that we encode within a QR code.
	uri = pyotp.TOTP(secret).provisioning_uri(
		name=email,
		issuer_name=get_relying_party_name(env)
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

class WebauthnStorageBackend(pywarp.backends.CredentialStorageBackend):
	def __init__(self, env):
		self.env = env
	def get_record(self, email, conn=None, c=None):
		# Get an existing record and parse the 'secret' column as JSON.
		if conn is None: conn, c = open_database(self.env, with_connection=True)
		c.execute('SELECT secret FROM mfa WHERE user_id=? AND type="webauthn"', (get_user_id(email, c),))
		config = c.fetchone()
		if config:
			try:
				return json.loads(config[0])
			except:
				pass
		return { }
	def update_record(self, email, fields):
		# Update the webauthn record in the database for this user by
		# merging the fields with the existing fields in the database.
		conn, c = open_database(self.env, with_connection=True)
		config = self.get_record(email, conn=conn, c=c)
		if config:
			# Merge and update.
			config.update(fields)
			config = json.dumps(config)
			c.execute('UPDATE mfa SET secret=? WHERE user_id=? AND type="webauthn"', (config, get_user_id(email, c),))
			conn.commit()
			return

		# Either there's no existing webauthn record or it's corrupted. Delete any existing record.
		# Then add a new record.
		c.execute('DELETE FROM mfa WHERE user_id=? AND type="webauthn"', (get_user_id(email, c),))
		c.execute('INSERT INTO mfa (user_id, type, secret, label) VALUES (?, ?, ?, ?)', (
			get_user_id(email, c), "webauthn",
			json.dumps(fields),
			"WebAuthn"))
		conn.commit()
	def save_challenge_for_user(self, email, challenge, type):
		self.update_record(email, { type + "challenge": base64.b64encode(challenge).decode("ascii") })
	def get_challenge_for_user(self, email, type):
		challenge = self.get_record(email).get(type + "challenge")
		if challenge: challenge = base64.b64decode(challenge.encode("ascii"))
		return challenge

def provision_webauthn(email, env):
	rp = pywarp.RelyingPartyManager(
		get_relying_party_name(env),
		rp_id=env["PRIMARY_HOSTNAME"], # must match hostname the control panel is served from
		credential_storage_backend=WebauthnStorageBackend(env))
	return rp.get_registration_options(email=email)

def validate_auth_mfa(email, request, env):
	# Validates that a login request satisfies any MFA modes
	# that have been enabled for the user's account. Returns
	# a tuple (status, [hints]). status is True for a successful
	# MFA login, False for a missing token. If status is False,
	# hints is an array of codes that indicate what the user
	# can try. Possible codes are:
	# "missing-totp-token"
	# "invalid-totp-token"

	mfa_state = get_mfa_state(email, env)

	# If no MFA modes are added, return True.
	if len(mfa_state) == 0:
		return (True, [])

	# Try the enabled MFA modes.
	hints = set()
	for mfa_mode in mfa_state:
		if mfa_mode["type"] == "totp":
			# Check that a token is present in the X-Auth-Token header.
			# If not, give a hint that one can be supplied.
			token = request.headers.get('x-auth-token')
			if not token:
				hints.add("missing-totp-token")
				continue

			# Check for a replay attack.
			if hmac.compare_digest(token, mfa_mode['mru_token'] or ""):
				# If the token fails, skip this MFA mode.
				hints.add("invalid-totp-token")
				continue

			# Check the token.
			totp = pyotp.TOTP(mfa_mode["secret"])
			if not totp.verify(token, valid_window=1):
				hints.add("invalid-totp-token")
				continue

			# On success, record the token to prevent a replay attack.
			set_mru_token(email, mfa_mode['id'], token, env)
			return (True, [])

	# On a failed login, indicate failure and any hints for what the user can do instead.
	return (False, list(hints))
