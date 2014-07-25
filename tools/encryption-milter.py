#!/usr/bin/env python3

import sys
import io
import re
import urllib.request, urllib.error
import tempfile
import shutil

import libmilter
import gnupg
import dns.resolver
from hashlib import sha224

# Start logging to syslog.
from syslog import syslog, openlog, LOG_MAIL
openlog('encryption-milter', facility=LOG_MAIL)

# Replace process title so it looks nicer in top.
try:
	import setproctitle
	setproctitle.setproctitle("encryption-milter")
except:
	pass

# Globals for DNS resolving. See:
# http://tools.ietf.org/html/draft-ietf-dane-openpgpkey-00
# http://tools.ietf.org/html/draft-ietf-dane-openpgpkey-usage-00
# https://github.com/letoams/openpgpkey-milter/
# I have not tested that this works at all.
resolver = dns.resolver.get_default_resolver()
#resolver.nameservers = [server]
openpgp_rtype = 65280  # draft value - changes when RFC

class EncryptionError(Exception):
	pass

class EncryptionMilter(libmilter.ForkMixin, libmilter.MilterProtocol):
	def __init__(self, opts=0, protos=0):
		libmilter.MilterProtocol.__init__(self, opts, protos)
		libmilter.ForkMixin.__init__(self)

		self.R = []  # list of recipient keys
		self.fp = io.BytesIO() # storage for incoming body

	def log(self, msg):
		print(msg)
		syslog('encryption-milter: ' + msg)

	def rcpt(self, rcpt_to, cmdDict):
		# Turn recipients into keys. If we don't have a key available,
		# then reject the message.
		try:
			self.R.extend(self.get_pgp_keys(rcpt_to))
			return libmilter.CONTINUE
		except EncryptionError as e:
			self.log(str(e))
			self.setReply(b'554', b'5.7.1', str(e).encode("utf8"))
			return libmilter.REJECT

	@libmilter.noReply
	def header(self, header, value, cmdDict):
		self.fp.write(header)
		self.fp.write(b': ')
		self.fp.write(value)
		self.fp.write(b'\n')
		return libmilter.CONTINUE

	@libmilter.noReply
	def eoh(self, cmdDict):
		self.fp.write(b'\n')
		return libmilter.CONTINUE

	@libmilter.noReply
	def body(self, chunk, cmdDict):
		self.fp.write(chunk)
		return libmilter.CONTINUE

	def eob(self, cmdDict):
		msg = self.fp.getvalue()

		gpgdir = tempfile.mkdtemp()
		gpg = gnupg.GPG(gnupghome=gpgdir)
		gpg.decode_errors = "ignore"
		try:
			# Add keys.
			for key in self.R:
				gpg.import_keys(key)

			# Target message encryption to all imported keys.
			fingerprints = ','.join(ikey['fingerprint'] for ikey in gpg.list_keys())

			# Encrypt message.
			enc_msg = gpg.encrypt(msg, fingerprints, always_trust=True)
			if enc_msg.data == '':
				# gpg binary and pythong wrapper is bad at giving us an error message
				raise Exception('Encryption failed for an unknown reason. GPG failed.')

			# Rewrite the message.

			self.addHeader(b'X-OpenPGPKey', b'Encrypted to key(s): ' + fingerprints.encode("ascii"))
			self.chgHeader(b'Subject', b'[pgp encrypted message]')
			self.replBody(enc_msg.data)

			return libmilter.CONTINUE

		except ValueError: #Exception as e:
			# Exceptions are thrown on things that would be temporary failures.
			# But by now it's too late to tell the user there was a problem?
			self.log(str(e))
			self.setReply(b'554', b'5.7.1', str(e).encode("utf8"))
			return libmilter.REJECT

		finally:
			shutil.rmtree(gpgdir)

	def get_pgp_keys(self, email_addr):
		keys = self.import_keys_from_keybase(email_addr)
		if keys: return keys

		keys = self.import_keys_from_dns(email_addr)
		if keys: return keys

		raise EncryptionError(email_addr.decode("utf8", "replace") + " does not have a known encryption key.")

	def import_keys_from_keybase(self, email_addr):
		# Extract the keybase username from the email address.
		m = re.search(rb"\+keybase=(.*)@", email_addr)
		if not m: return None
		keybase_username = m.group(1)

		# Query keybase.
		try:
			req = urllib.request.urlopen("https://keybase.io/%s/key.asc" % keybase_username.decode("ascii", "error"), timeout=20, cadefault=True)
			openpgpkey = req.read()
		except Exception as e:
			if isinstance(e, urllib.error.HTTPError) and e.code == 404:
				e = "User not found."
			raise EncryptionError("Error getting public key for %s at Keybase.io: %s" % (keybase_username.decode("utf8", "replace"), str(e)))

		# Return the key.
		self.log("got keybase.io key for %s" % keybase_username.decode("utf8", "replace"))
		return [openpgpkey]

	def import_keys_from_dns(self, email_addr):
		(username, domainname) = email_addr.split(b'@')
		qname = '%s._openpgpkey.%s' % (sha224(username).hexdigest(), domainname)

		try:
			response = dns.resolver.query(qname, openpgp_rtype)
		except dns.resolver.NoNameservers:
			# could not connect to nameserver
			raise EncryptionError("Could not connect to nameserver.")
		except (dns.resolver.NXDOMAIN, dns.resolver.NoAnswer):
			# host did not have an answer for this query; not sure what the
			# difference is between the two exceptions
			return None

		if len(result) == 0:
			# empty answer? probably not possible...
			return None

		# Return all keys found in DNS.
		return [str(value) for value in result]


def runMilter():
	# Adapted from the python-libmilter example at
	# https://github.com/crustymonkey/python-libmilter/blob/master/examples/testmilter.py

	import signal, traceback

	# Create the milter. Use the ForkFactor to handle each mail in a separate process.
	f = libmilter.ForkFactory('inet:127.0.0.1:8892', EncryptionMilter,
		libmilter.SMFIF_ADDHDRS | libmilter.SMFIF_CHGHDRS | libmilter.SMFIF_CHGBODY)

	# Add a signal handler to cleanly exit.
	def sigHandler(num, frame):
		f.close()
		sys.exit(0)
	signal.signal(signal.SIGINT, sigHandler)

	# Start the milter.
	try:
		f.run()
	except Exception as e:
		f.close()
		raise

if __name__ == '__main__':
	runMilter()
