#!/usr/bin/python3

import os, os.path, re, json

from functools import wraps

from flask import Flask, request, render_template, abort, Response, send_from_directory

import auth, utils
from mailconfig import get_mail_users, get_mail_users_ex, get_admins, add_mail_user, set_mail_password, remove_mail_user
from mailconfig import get_mail_user_privileges, add_remove_mail_user_privilege
from mailconfig import get_mail_aliases, get_mail_aliases_ex, get_mail_domains, add_mail_alias, remove_mail_alias

# Create a worker pool for the status checks. The pool should
# live across http requests so we don't baloon the system with
# processes.
import multiprocessing.pool
pool = multiprocessing.pool.Pool(processes=10)

env = utils.load_environment()

auth_service = auth.KeyAuthService()

# We may deploy via a symbolic link, which confuses flask's template finding.
me = __file__
try:
	me = os.readlink(__file__)
except OSError:
	pass

app = Flask(__name__, template_folder=os.path.abspath(os.path.join(os.path.dirname(me), "templates")))

# Decorator to protect views that require a user with 'admin' privileges.
def authorized_personnel_only(viewfunc):
	@wraps(viewfunc)
	def newview(*args, **kwargs):
		# Authenticate the passed credentials, which is either the API key or a username:password pair.
		error = None
		try:
			email, privs = auth_service.authenticate(request, env)
		except ValueError as e:
			# Authentication failed.
			privs = []
			error = str(e)

		# Authorized to access an API view?
		if "admin" in privs:
			# Call view func.
			return viewfunc(*args, **kwargs)
		elif not error:
			error = "You are not an administrator."

		# Not authorized. Return a 401 (send auth) and a prompt to authorize by default.
		status = 401
		headers = {
			'WWW-Authenticate': 'Basic realm="{0}"'.format(auth_service.auth_realm),
			'X-Reason': error,
		}

		if request.headers.get('X-Requested-With') == 'XMLHttpRequest':
			# Don't issue a 401 to an AJAX request because the user will
			# be prompted for credentials, which is not helpful.
			status = 403
			headers = None

		if request.headers.get('Accept') in (None, "", "*/*"):
			# Return plain text output.
			return Response(error+"\n", status=status, mimetype='text/plain', headers=headers)
		else:
			# Return JSON output.
			return Response(json.dumps({
				"status": "error",
				"reason": error,
				})+"\n", status=status, mimetype='application/json', headers=headers)

	return newview

@app.errorhandler(401)
def unauthorized(error):
	return auth_service.make_unauthorized_response()

def json_response(data):
	return Response(json.dumps(data, indent=2, sort_keys=True)+'\n', status=200, mimetype='application/json')

###################################

# Control Panel (unauthenticated views)

@app.route('/')
def index():
	# Render the control panel. This route does not require user authentication
	# so it must be safe!

	no_users_exist = (len(get_mail_users(env)) == 0)
	no_admins_exist = (len(get_admins(env)) == 0)

	utils.fix_boto() # must call prior to importing boto
	import boto.s3
	backup_s3_hosts = [(r.name, r.endpoint) for r in boto.s3.regions()]

	return render_template('index.html',
		hostname=env['PRIMARY_HOSTNAME'],
		storage_root=env['STORAGE_ROOT'],
		no_users_exist=no_users_exist,
		no_admins_exist=no_admins_exist,
		backup_s3_hosts=backup_s3_hosts,
	)

@app.route('/me')
def me():
	# Is the caller authorized?
	try:
		email, privs = auth_service.authenticate(request, env)
	except ValueError as e:
		return json_response({
			"status": "invalid",
			"reason": str(e),
			})

	resp = {
		"status": "ok",
		"email": email,
		"privileges": privs,
	}

	# Is authorized as admin? Return an API key for future use.
	if "admin" in privs:
		resp["api_key"] = auth_service.create_user_key(email, env)

	# Return.
	return json_response(resp)

# MAIL

@app.route('/mail/users')
@authorized_personnel_only
def mail_users():
	if request.args.get("format", "") == "json":
		return json_response(get_mail_users_ex(env, with_archived=True, with_slow_info=True))
	else:
		return "".join(x+"\n" for x in get_mail_users(env))

@app.route('/mail/users/add', methods=['POST'])
@authorized_personnel_only
def mail_users_add():
	try:
		return add_mail_user(request.form.get('email', ''), request.form.get('password', ''), request.form.get('privileges', ''), env)
	except ValueError as e:
		return (str(e), 400)

@app.route('/mail/users/password', methods=['POST'])
@authorized_personnel_only
def mail_users_password():
	try:
		return set_mail_password(request.form.get('email', ''), request.form.get('password', ''), env)
	except ValueError as e:
		return (str(e), 400)

@app.route('/mail/users/remove', methods=['POST'])
@authorized_personnel_only
def mail_users_remove():
	return remove_mail_user(request.form.get('email', ''), env)


@app.route('/mail/users/privileges')
@authorized_personnel_only
def mail_user_privs():
	privs = get_mail_user_privileges(request.args.get('email', ''), env)
	if isinstance(privs, tuple): return privs # error
	return "\n".join(privs)

@app.route('/mail/users/privileges/add', methods=['POST'])
@authorized_personnel_only
def mail_user_privs_add():
	return add_remove_mail_user_privilege(request.form.get('email', ''), request.form.get('privilege', ''), "add", env)

@app.route('/mail/users/privileges/remove', methods=['POST'])
@authorized_personnel_only
def mail_user_privs_remove():
	return add_remove_mail_user_privilege(request.form.get('email', ''), request.form.get('privilege', ''), "remove", env)


@app.route('/mail/aliases')
@authorized_personnel_only
def mail_aliases():
	if request.args.get("format", "") == "json":
		return json_response(get_mail_aliases_ex(env))
	else:
		return "".join(address+"\t"+receivers+"\t"+(senders or "")+"\n" for address, receivers, senders in get_mail_aliases(env))

@app.route('/mail/aliases/add', methods=['POST'])
@authorized_personnel_only
def mail_aliases_add():
	return add_mail_alias(
		request.form.get('address', ''),
		request.form.get('forwards_to', ''),
		request.form.get('permitted_senders', ''),
		env,
		update_if_exists=(request.form.get('update_if_exists', '') == '1')
		)

@app.route('/mail/aliases/remove', methods=['POST'])
@authorized_personnel_only
def mail_aliases_remove():
	return remove_mail_alias(request.form.get('address', ''), env)

@app.route('/mail/domains')
@authorized_personnel_only
def mail_domains():
    return "".join(x+"\n" for x in get_mail_domains(env))

# DNS

@app.route('/dns/zones')
@authorized_personnel_only
def dns_zones():
	from dns_update import get_dns_zones
	return json_response([z[0] for z in get_dns_zones(env)])

@app.route('/dns/update', methods=['POST'])
@authorized_personnel_only
def dns_update():
	from dns_update import do_dns_update
	try:
		return do_dns_update(env, force=request.form.get('force', '') == '1')
	except Exception as e:
		return (str(e), 500)

@app.route('/dns/secondary-nameserver')
@authorized_personnel_only
def dns_get_secondary_nameserver():
	from dns_update import get_custom_dns_config, get_secondary_dns
	return json_response({ "hostnames": get_secondary_dns(get_custom_dns_config(env), mode=None) })

@app.route('/dns/secondary-nameserver', methods=['POST'])
@authorized_personnel_only
def dns_set_secondary_nameserver():
	from dns_update import set_secondary_dns
	try:
		return set_secondary_dns([ns.strip() for ns in re.split(r"[, ]+", request.form.get('hostnames') or "") if ns.strip() != ""], env)
	except ValueError as e:
		return (str(e), 400)

@app.route('/dns/custom')
@authorized_personnel_only
def dns_get_records(qname=None, rtype=None):
	from dns_update import get_custom_dns_config
	return json_response([
	{
		"qname": r[0],
		"rtype": r[1],
		"value": r[2],
	}
	for r in get_custom_dns_config(env)
	if r[0] != "_secondary_nameserver"
		and (not qname or r[0] == qname)
		and (not rtype or r[1] == rtype) ])

@app.route('/dns/custom/<qname>', methods=['GET', 'POST', 'PUT', 'DELETE'])
@app.route('/dns/custom/<qname>/<rtype>', methods=['GET', 'POST', 'PUT', 'DELETE'])
@authorized_personnel_only
def dns_set_record(qname, rtype="A"):
	from dns_update import do_dns_update, set_custom_dns_record
	try:
		# Normalize.
		rtype = rtype.upper()

		# Read the record value from the request BODY, which must be
		# ASCII-only. Not used with GET.
		value = request.stream.read().decode("ascii", "ignore").strip()

		if request.method == "GET":
			# Get the existing records matching the qname and rtype.
			return dns_get_records(qname, rtype)

		elif request.method in ("POST", "PUT"):
			# There is a default value for A/AAAA records.
			if rtype in ("A", "AAAA") and value == "":
				value = request.environ.get("HTTP_X_FORWARDED_FOR") # normally REMOTE_ADDR but we're behind nginx as a reverse proxy

			# Cannot add empty records.
			if value == '':
				return ("No value for the record provided.", 400)

			if request.method == "POST":
				# Add a new record (in addition to any existing records
				# for this qname-rtype pair).
				action = "add"
			elif request.method == "PUT":
				# In REST, PUT is supposed to be idempotent, so we'll
				# make this action set (replace all records for this
				# qname-rtype pair) rather than add (add a new record).
				action = "set"

		elif request.method == "DELETE":
			if value == '':
				# Delete all records for this qname-type pair.
				value = None
			else:
				# Delete just the qname-rtype-value record exactly.
				pass
			action = "remove"

		if set_custom_dns_record(qname, rtype, value, action, env):
			return do_dns_update(env) or "Something isn't right."
		return "OK"

	except ValueError as e:
		return (str(e), 400)

@app.route('/dns/dump')
@authorized_personnel_only
def dns_get_dump():
	from dns_update import build_recommended_dns
	return json_response(build_recommended_dns(env))

# SSL

@app.route('/ssl/csr/<domain>', methods=['POST'])
@authorized_personnel_only
def ssl_get_csr(domain):
	from web_update import create_csr
	ssl_private_key = os.path.join(os.path.join(env["STORAGE_ROOT"], 'ssl', 'ssl_private_key.pem'))
	return create_csr(domain, ssl_private_key, env)

@app.route('/ssl/install', methods=['POST'])
@authorized_personnel_only
def ssl_install_cert():
	from web_update import install_cert
	domain = request.form.get('domain')
	ssl_cert = request.form.get('cert')
	ssl_chain = request.form.get('chain')
	return install_cert(domain, ssl_cert, ssl_chain, env)

# WEB

@app.route('/web/domains')
@authorized_personnel_only
def web_get_domains():
	from web_update import get_web_domains_info
	return json_response(get_web_domains_info(env))

@app.route('/web/update', methods=['POST'])
@authorized_personnel_only
def web_update():
	from web_update import do_web_update
	return do_web_update(env)

# System

@app.route('/system/version', methods=["GET"])
@authorized_personnel_only
def system_version():
	from status_checks import what_version_is_this
	try:
		return what_version_is_this(env)
	except Exception as e:
		return (str(e), 500)

@app.route('/system/latest-upstream-version', methods=["POST"])
@authorized_personnel_only
def system_latest_upstream_version():
	from status_checks import get_latest_miab_version
	try:
		return get_latest_miab_version()
	except Exception as e:
		return (str(e), 500)

@app.route('/system/status', methods=["POST"])
@authorized_personnel_only
def system_status():
	from status_checks import run_checks
	class WebOutput:
		def __init__(self):
			self.items = []
		def add_heading(self, heading):
			self.items.append({ "type": "heading", "text": heading, "extra": [] })
		def print_ok(self, message):
			self.items.append({ "type": "ok", "text": message, "extra": [] })
		def print_error(self, message):
			self.items.append({ "type": "error", "text": message, "extra": [] })
		def print_warning(self, message):
			self.items.append({ "type": "warning", "text": message, "extra": [] })
		def print_line(self, message, monospace=False):
			self.items[-1]["extra"].append({ "text": message, "monospace": monospace })
	output = WebOutput()
	run_checks(False, env, output, pool)
	return json_response(output.items)

@app.route('/system/updates')
@authorized_personnel_only
def show_updates():
	from status_checks import list_apt_updates
	return "".join(
		"%s (%s)\n"
		% (p["package"], p["version"])
		for p in list_apt_updates())

@app.route('/system/update-packages', methods=["POST"])
@authorized_personnel_only
def do_updates():
	utils.shell("check_call", ["/usr/bin/apt-get", "-qq", "update"])
	return utils.shell("check_output", ["/usr/bin/apt-get", "-y", "upgrade"], env={
		"DEBIAN_FRONTEND": "noninteractive"
	})

@app.route('/system/backup/status')
@authorized_personnel_only
def backup_status():
	from backup import backup_status
	return json_response(backup_status(env))

@app.route('/system/backup/config', methods=["GET"])
@authorized_personnel_only
def backup_get_custom():
	from backup import get_backup_config
	return json_response(get_backup_config(env, for_ui=True))

@app.route('/system/backup/config', methods=["POST"])
@authorized_personnel_only
def backup_set_custom():
	from backup import backup_set_custom
	return json_response(backup_set_custom(env,
		request.form.get('target', ''),
		request.form.get('target_user', ''),
		request.form.get('target_pass', ''),
		request.form.get('min_age', '')
	))

@app.route('/system/privacy', methods=["GET"])
@authorized_personnel_only
def privacy_status_get():
	config = utils.load_settings(env)
	return json_response(config.get("privacy", True))

@app.route('/system/privacy', methods=["POST"])
@authorized_personnel_only
def privacy_status_set():
	config = utils.load_settings(env)
	config["privacy"] = (request.form.get('value') == "private")
	utils.write_settings(config, env)
	return "OK"

# MUNIN

@app.route('/munin/')
@app.route('/munin/<path:filename>')
@authorized_personnel_only
def munin(filename=""):
	# Checks administrative access (@authorized_personnel_only) and then just proxies
	# the request to static files.
	if filename == "": filename = "index.html"
	return send_from_directory("/var/cache/munin/www", filename)

# APP

if __name__ == '__main__':
	if "DEBUG" in os.environ: app.debug = True
	if "APIKEY" in os.environ: auth_service.key = os.environ["APIKEY"]

	if not app.debug:
		app.logger.addHandler(utils.create_syslog_handler())

	# For testing on the command line, you can use `curl` like so:
	#    curl --user $(</var/lib/mailinabox/api.key): http://localhost:10222/mail/users
	auth_service.write_key()

	# For testing in the browser, you can copy the API key that's output to the
	# debug console and enter that as the username
	app.logger.info('API key: ' + auth_service.key)

	# Start the application server. Listens on 127.0.0.1 (IPv4 only).
	app.run(port=10222)
