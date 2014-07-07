#!/usr/bin/python3

# Helps you purchase a SSL certificate from Gandi.net using
# their API.
#
# Before you begin:
#  1) Create an account on Gandi.net.
#  2) Pre-pay $16 into your account at https://www.gandi.net/prepaid/operations. Wait until the payment goes through.
#  3) Activate your API key first on the test platform (wait a while, refresh the page) and then activate the production API at https://www.gandi.net/admin/api_key.

import sys, re,  os.path, urllib.request
import xmlrpc.client
import rtyaml

from utils import load_environment, shell
from web_update import get_web_domains, get_domain_ssl_files, get_web_root
from whats_next import check_certificate

def buy_ssl_certificate(api_key, domain, command, env):
	if domain != env['PRIMARY_HOSTNAME'] \
		and domain not in get_web_domains(env):
		raise ValueError("Domain is not %s or a domain we're serving a website for." % env['PRIMARY_HOSTNAME'])

	# Initialize.

	gandi = xmlrpc.client.ServerProxy('https://rpc.gandi.net/xmlrpc/')

	try:
		existing_certs = gandi.cert.list(api_key)
	except Exception as e:
		if "Invalid API key" in str(e):
			print("Invalid API key. Check that you copied the API Key correctly from https://www.gandi.net/admin/api_key.")
			sys.exit(1)
		else:
			raise

	# Where is the SSL cert stored?

	ssl_key, ssl_certificate, ssl_csr_path = get_domain_ssl_files(domain, env)	

	# Have we already created a cert for this domain?

	for cert in existing_certs:
		if cert['cn'] == domain:
			break
	else:
		# No existing cert found. Purchase one.
		if command != 'purchase':
			print("No certificate or order found yet. If you haven't yet purchased a certificate, run ths script again with the 'purchase' command. Otherwise wait a moment and try again.")
			sys.exit(1)
		else:
			# Start an order for a single standard SSL certificate.
			# Use DNS validation. Web-based validation won't work because they
			# require a file on HTTP but not HTTPS w/o redirects and we don't
			# serve anything plainly over HTTP. Email might be another way but
			# DNS is easier to automate.
			op = gandi.cert.create(api_key, {
				"csr": open(ssl_csr_path).read(),
				"dcv_method": "dns",
				"duration": 1, # year?
				"package": "cert_std_1_0_0",
				})
			print("An SSL certificate has been ordered.")
			print()
			print(op)
			print()
			print("In a moment please run this script again with the 'setup' command.")

	if cert['status'] == 'pending':
		# Get the information we need to update our DNS with a code so that
		# Gandi can verify that we own the domain.

		dcv = gandi.cert.get_dcv_params(api_key, {
				"csr": open(ssl_csr_path).read(),
				"cert_id": cert['id'],
				"dcv_method": "dns",
				"duration": 1, # year?
				"package": "cert_std_1_0_0",
				})
		if dcv["dcv_method"] != "dns":
			raise Exception("Certificate ordered with an unknown validation method.")

		# Update our DNS data.

		dns_config = env['STORAGE_ROOT'] + '/dns/custom.yaml'
		if os.path.exists(dns_config):
			dns_records = rtyaml.load(open(dns_config))
		else:
			dns_records = { }

		qname = dcv['md5'] + '.' + domain
		value = dcv['sha1'] + '.comodoca.com.'
		dns_records[qname] = { "CNAME": value }

		with open(dns_config, 'w') as f:
			f.write(rtyaml.dump(dns_records))

		shell('check_call', ['tools/dns_update'])

		# Okay, done with this step.

		print("DNS has been updated. Gandi will check within 60 minutes.")
		print()
		print("See https://www.gandi.net/admin/ssl/%d/details for the status of this order." % cert['id'])

	elif cert['status'] == 'valid':
		# The certificate is ready.

		# Check before we overwrite something we shouldn't.
		if os.path.exists(ssl_certificate):
			cert_status = check_certificate(None, ssl_certificate)
			if cert_status != "SELF-SIGNED":
				print("Please back up and delete the file %s so I can save your new certificate." % ssl_certificate)
				sys.exit(1)

		# Form the certificate.

		# The certificate comes as a long base64-encoded string. Break in
		# into lines in the usual way.
		pem = "-----BEGIN CERTIFICATE-----\n"
		pem += "\n".join(chunk for chunk in re.split(r"(.{64})", cert['cert']) if chunk != "")
		pem += "\n-----END CERTIFICATE-----\n\n"

		# Append intermediary certificates.
		pem += urllib.request.urlopen("https://www.gandi.net/static/CAs/GandiStandardSSLCA.pem").read().decode("ascii")

		# Write out.

		with open(ssl_certificate, "w") as f:
			f.write(pem)

		print("The certificate has been installed in %s. Restarting services..." % ssl_certificate)

		# Restart dovecot and if this is for PRIMARY_HOSTNAME.

		if domain == env['PRIMARY_HOSTNAME']:
			shell('check_call', ["/usr/sbin/service", "dovecot", "restart"])
			shell('check_call', ["/usr/sbin/service", "postfix", "restart"])

		# Restart nginx in all cases.

		shell('check_call', ["/usr/sbin/service", "nginx", "restart"])

	else:
		print("The certificate has an unknown status. Please check https://www.gandi.net/admin/ssl/%d/details for the status of this order." % cert['id'])

if __name__ == "__main__":
	if len(sys.argv) < 4:
		print("Usage: python management/buy_certificate.py gandi_api_key domain_name {purchase, setup}")
		sys.exit(1)
	api_key = sys.argv[1]
	domain_name = sys.argv[2]
	cmd = sys.argv[3]
	buy_ssl_certificate(api_key, domain_name, cmd, load_environment())

