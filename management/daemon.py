#!/usr/bin/python3

import os, os.path, re, json

from functools import wraps

from flask import Flask, request, render_template, abort, Response

import auth, utils
from mailconfig import get_mail_users, get_mail_users_ex, get_admins, add_mail_user, set_mail_password, remove_mail_user
from mailconfig import get_mail_user_privileges, add_remove_mail_user_privilege
from mailconfig import get_mail_aliases, get_mail_aliases_ex, get_mail_domains, add_mail_alias, remove_mail_alias

env = utils.load_environment()

auth_service = auth.KeyAuthService()

# We may deploy via a symbolic link, which confuses flask's template finding.
me = __file__
try:
	me = os.readlink(__file__)
except OSError:
	pass

app = Flask(__name__, template_folder=os.path.abspath(os.path.join(os.path.dirname(me), "templates")))

# Decorator to protect views that require authentication.
def authorized_personnel_only(viewfunc):
	@wraps(viewfunc)
	def newview(*args, **kwargs):
		# Check if the user is authorized.
		authorized_status = auth_service.is_authenticated(request, env)
		if authorized_status == "OK":
			# Authorized. Call view func.	
			return viewfunc(*args, **kwargs)

		# Not authorized. Return a 401 (send auth) and a prompt to authorize by default.
		status = 401
		headers = { 'WWW-Authenticate': 'Basic realm="{0}"'.format(auth_service.auth_realm) }

		if request.headers.get('X-Requested-With') == 'XMLHttpRequest':
			# Don't issue a 401 to an AJAX request because the user will
			# be prompted for credentials, which is not helpful.
			status = 403
			headers = None

		if request.headers.get('Accept') in (None, "", "*/*"):
			# Return plain text output.
			return Response(authorized_status+"\n", status=status, mimetype='text/plain', headers=headers)
		else:
			# Return JSON output.
			return Response(json.dumps({
				"status": "error",
				"reason": authorized_status
				}+"\n"), status=status, mimetype='application/json', headers=headers)

	return newview

@app.errorhandler(401)
def unauthorized(error):
	return auth_service.make_unauthorized_response()

def json_response(data):
	return Response(json.dumps(data), status=200, mimetype='application/json')

###################################

# Control Panel (unauthenticated views)

@app.route('/')
def index():
	# Render the control panel. This route does not require user authentication
	# so it must be safe!
	no_admins_exist = (len(get_admins(env)) == 0)
	return render_template('index.html',
		hostname=env['PRIMARY_HOSTNAME'],
		storage_root=env['STORAGE_ROOT'],
		no_admins_exist=no_admins_exist,
	)

@app.route('/me')
def me():
	# Is the caller authorized?
	authorized_status = auth_service.is_authenticated(request, env)
	if authorized_status != "OK":
		return json_response({
			"status": "not-authorized",
			"reason": authorized_status,
			})
	return json_response({
		"status": "authorized",
		"api_key": auth_service.key,
		})

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
		return "".join(x+"\t"+y+"\n" for x, y in get_mail_aliases(env))

@app.route('/mail/aliases/add', methods=['POST'])
@authorized_personnel_only
def mail_aliases_add():
	return add_mail_alias(
		request.form.get('source', ''),
		request.form.get('destination', ''),
		env,
		update_if_exists=(request.form.get('update_if_exists', '') == '1')
		)

@app.route('/mail/aliases/remove', methods=['POST'])
@authorized_personnel_only
def mail_aliases_remove():
	return remove_mail_alias(request.form.get('source', ''), env)

@app.route('/mail/domains')
@authorized_personnel_only
def mail_domains():
    return "".join(x+"\n" for x in get_mail_domains(env))

# DNS

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
	from dns_update import get_custom_dns_config
	return json_response({ "hostname": get_custom_dns_config(env).get("_secondary_nameserver") })

@app.route('/dns/secondary-nameserver', methods=['POST'])
@authorized_personnel_only
def dns_set_secondary_nameserver():
	from dns_update import set_secondary_dns
	try:
		return set_secondary_dns(request.form.get('hostname'), env)
	except ValueError as e:
		return (str(e), 400)


@app.route('/dns/set/<qname>', methods=['POST'])
@app.route('/dns/set/<qname>/<rtype>', methods=['POST'])
@app.route('/dns/set/<qname>/<rtype>/<value>', methods=['POST'])
@authorized_personnel_only
def dns_set_record(qname, rtype="A", value=None):
	from dns_update import do_dns_update, set_custom_dns_record
	try:
		# Get the value from the URL, then the POST parameters, or if it is not set then
		# use the remote IP address of the request --- makes dynamic DNS easy. To clear a
		# value, '' must be explicitly passed.
		if value is None:
			value = request.form.get("value")
		if value is None:
			value = request.environ.get("HTTP_X_FORWARDED_FOR") # normally REMOTE_ADDR but we're behind nginx as a reverse proxy
		if value == '' or value == '__delete__':
			# request deletion
			value = None
		if set_custom_dns_record(qname, rtype, value, env):
			return do_dns_update(env)
		return "OK"
	except ValueError as e:
		return (str(e), 400)

@app.route('/dns/dump')
@authorized_personnel_only
def dns_get_dump():
	from dns_update import build_recommended_dns
	return json_response(build_recommended_dns(env))

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
	run_checks(env, output)
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

