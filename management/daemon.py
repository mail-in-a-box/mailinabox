#!/usr/bin/python3

import os, os.path, re, json

from functools import wraps

from flask import Flask, request, render_template, abort, Response

import auth, utils
from mailconfig import get_mail_users, add_mail_user, set_mail_password, remove_mail_user, get_archived_mail_users
from mailconfig import get_mail_user_privileges, add_remove_mail_user_privilege
from mailconfig import get_mail_aliases, get_mail_domains, add_mail_alias, remove_mail_alias

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
	return render_template('index.html',
		hostname=env['PRIMARY_HOSTNAME'],
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
		return json_response(get_mail_users(env, as_json=True) + get_archived_mail_users(env))
	else:
		return "".join(x+"\n" for x in get_mail_users(env))

@app.route('/mail/users/add', methods=['POST'])
@authorized_personnel_only
def mail_users_add():
	return add_mail_user(request.form.get('email', ''), request.form.get('password', ''), request.form.get('privileges', ''), env)

@app.route('/mail/users/password', methods=['POST'])
@authorized_personnel_only
def mail_users_password():
	return set_mail_password(request.form.get('email', ''), request.form.get('password', ''), env)

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
		return json_response(get_mail_aliases(env, as_json=True))
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

@app.route('/dns/dump')
@authorized_personnel_only
def dns_get_dump():
	from dns_update import build_recommended_dns
	return json_response(build_recommended_dns(env))

# WEB

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
		def print_line(self, message, monospace=False):
			self.items[-1]["extra"].append({ "text": message, "monospace": monospace })
	output = WebOutput()
	run_checks(env, output)
	return json_response(output.items)

@app.route('/system/updates')
@authorized_personnel_only
def show_updates():
	utils.shell("check_call", ["/usr/bin/apt-get", "-qq", "update"])
	simulated_install = utils.shell("check_output", ["/usr/bin/apt-get", "-qq", "-s", "upgrade"])
	pkgs = []
	for line in simulated_install.split('\n'):
		if re.match(r'^Conf .*', line): continue # remove these lines, not informative
		line = re.sub(r'^Inst (.*) \[(.*)\] \((\S*).*', r'Updated Package Available: \1 (\3)', line) # make these lines prettier
		pkgs.append(line)
	return "\n".join(pkgs)

@app.route('/system/update-packages', methods=["POST"])
@authorized_personnel_only
def do_updates():
	utils.shell("check_call", ["/usr/bin/apt-get", "-qq", "update"])
	return utils.shell("check_output", ["/usr/bin/apt-get", "-y", "upgrade"], env={
		"DEBIAN_FRONTEND": "noninteractive"
	})

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

	app.run(port=10222)

