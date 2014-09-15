#!/usr/bin/python3

# A Mailpile multiplexer
# ----------------------
#
# Mailpile has no built-in notion of user authentication. It's
# a single-user thing. This file provides a proxy server around
# Mailpile that interfaces with Mail-in-a-Box user authentication.
# When a user logs in, a new Mailpile instance is forked and we
# proxy to that Mailpile for that user's session.

import sys, os, os.path, re, urllib.request, urllib.parse, urllib.error, time, subprocess

from flask import Flask, request, session, render_template, redirect, abort
app = Flask(__name__)

sys.path.insert(0, 'management')
import utils
env = utils.load_environment()

running_mailpiles = { }

@app.route('/')
def index():
	return render_template('frameset.html')

@app.route('/status')
def status():
	# If the user is not logged in, show a blank page because we'll
	# display the login form in the mailpile frame.
	if "auth" not in session:
		return "<html><body></body></html>"

	# Show the user's current logged in status.
	return render_template('login_status.html', auth=session.get("auth"))

@app.route('/refresh-frameset')
def refresh_frameset():
	# Force a reload of the frameset from within a frame.
	return """
<html>
	<body>
		<script>
			top.location.reload();
		</script>
	</body>
</html>
"""

@app.route('/logout')
def logout():
	session.pop("auth", None)
	return redirect('/refresh-frameset')

@app.route('/mailpile', methods=['GET', 'POST'])
def mailpile():
	# If the user is not logged in, show a login form.
	if "auth" not in session:
		return login_form()
	else:
		return proxy_request_to_mailpile('/')

@app.route('/mailpile/<path:path>', methods=['GET', 'POST'])
def mailpile2(path):
	# On inside pages, if the user is not logged in, then we can't
	# really safely redirect to a login page because we don't know
	# what sort of resource is being requested.
	if "auth" not in session:
		abort(403)
	else:
		return proxy_request_to_mailpile('/' + path)

def login_form():
	if request.method == 'GET':
		# Show the login form.
		return render_template('login.html', hostname=env["PRIMARY_HOSTNAME"])
	else:
		# Process the login form.
		if request.form.get('email', '').strip() == '' or request.form.get('password', '').strip() == '':
			error = "Enter your email address and password."
		else:
			# Get form fields.
			email = request.form['email'].strip()
			pw = request.form['password'].strip()
			remember = request.form.get('remember')

			# See if credentials are good.
			try:
				# Use doveadm to check credentials.
				utils.shell('check_call', [
					"/usr/bin/doveadm",
					"auth", "test",
					email, pw
					])

				# If no exception was thrown, credentials are good!
				if remember: session.permanent = True
				session['auth'] = {
					"email": email,
				}

				# Use Javascript to reload the whole frameset so that we
				# can trigger a reload of the top frame that shows login
				# status.
				return redirect('/refresh-frameset')

			except:
				# Login failed.
				error = "Email address & password did not match."

		return render_template('login.html',
			hostname=env["PRIMARY_HOSTNAME"],
			error=error,
			email=request.form.get("email"), password=request.form.get("password"), remember=request.form.get("remember"))

def proxy_request_to_mailpile(path):
	# Proxy the request.
	port = get_mailpile_port(session['auth']['email'])

	# Munge the headers. (http://www.snip2code.com/Snippet/45977/Simple-Flask-Proxy/)
	headers = dict([(key.upper(), value) for key, value in request.headers.items() if key.upper() != "HOST"])

	# Is this a POST? Re-create the request body.
	data = None
	if request.method == "POST":
		data = urllib.parse.urlencode(list(request.form.items(multi=True)), encoding='utf8').encode('utf8')
		headers['CONTENT-LENGTH'] = str(len(data))

	# Configure request.
	req = urllib.request.Request(
		"http://localhost:%d%s" % (port, path),
		data,
		headers=headers,
		)

	# Execute request.
	try:
		response = urllib.request.urlopen(req)
		body = response.read()
		headers = dict(response.getheaders())
		content_type = response.getheader("content-type", default="")
		response_status = response.status
	except urllib.error.HTTPError as e:
		# Exceptions (400s, 500s, etc) are response objects too?
		body = e.read()
		headers = dict(e.headers)
		content_type = "?/?" # don't do any munging
		response_status = e.code

	# Munge the response.

	def rewrite_url(href):
		# Make the URL absolute.
		import urllib.parse
		href2 = urllib.parse.urljoin(path, href.decode("utf8"))
		if urllib.parse.urlparse(href2).scheme == "":
			# This was a relative URL that we are proxying.
			return b'/mailpile' + href2.encode("utf8")
		return href

	if content_type.startswith("text/html"):
		# Rewrite URLs in HTML responses.
		body = re.sub(rb" (href|src|HREF|SRC|action)=('[^']*'|\"[^\"]*\")",
			lambda m : b' ' + m.group(1) + b'=' + m.group(2)[0:1] + rewrite_url(m.group(2)[1:-1]) + m.group(2)[0:1],
			body)

	if content_type.startswith("text/css"):
		# Rewrite URLs in CSS responses.
		body = re.sub(rb"url\('([^)]*)'\)", lambda m : b"url('" + rewrite_url(m.group(1)) + b"')", body)

	if content_type.startswith("text/javascript"):
		# Rewrite URLs in Javascript responses.
		body = re.sub(rb"/(?:api|async)[/\w]*", lambda m : rewrite_url(m.group(0)), body)
		body = re.sub(rb"((?:message_draft|message_sent|tags)\s+:\s+\")([^\"]+)", lambda m : m.group(1) + rewrite_url(m.group(2)), body)

	#if content_type == "application/json":
	#	body = json.loads(body.decode('utf8'))
	#	def procobj(obj, is_urls=False):
	#		if not isinstance(obj, dict): return
	#		for k, v in obj.items():
	#			if is_urls: obj[k] = rewrite_url(v.encode('utf8')).decode('utf8')
	#			procobj(v, is_urls=(k == "urls"))
	#	procobj(body)
	#	body = json.dumps(body).encode('utf8')

	# Pass back response to the client.
	return (body, response_status, headers)

def get_mailpile_port(emailaddr):
	if emailaddr not in running_mailpiles:
		running_mailpiles[emailaddr] = spawn_mailpile(emailaddr)
	return running_mailpiles[emailaddr]

def spawn_mailpile(emailaddr):
	# Spawn a new instance of Mailpile that will automatically die
	# when this process exits because it'll be reading from a pipe
	# connected to this process.

	# Prepare mailpile.

	user, domain = emailaddr.split("@")
	mp_home = os.path.join(env['STORAGE_ROOT'], 'mail/mailpile', utils.safe_domain_name(domain), utils.safe_domain_name(user))
	maildir = os.path.join(env['STORAGE_ROOT'], 'mail/mailboxes', utils.safe_domain_name(domain), utils.safe_domain_name(user))
	port = 10300 + len(running_mailpiles)

	def mp(*args):
		cmd = [os.path.join(os.path.dirname(__file__), '../externals/Mailpile/mp')] + list(args)
		utils.shell("check_call", cmd, env={ "MAILPILE_HOME": mp_home })

	os.makedirs(mp_home, exist_ok=True)
	mp("add", maildir)
	mp("rescan")
	mp("set", "profiles.0.email=%s" % emailaddr)
	mp("set", "profiles.0.name=%s" % emailaddr)
	mp("set", "sys.http_port=%d" % port)

	# Span mailpile in a way that lets us control its stdin.
	mailpile_proc = \
		subprocess.Popen(
			[
				os.path.join(os.path.dirname(__file__), '../externals/Mailpile/mp'),
			],
			stdin=subprocess.PIPE,
			#stdout=subprocess.DEVNULL,
			env={ "MAILPILE_HOME": mp_home }
		)

	# Give mailpile time to start before trying to send over a request.
	time.sleep(3)

	return port

# APP

if __name__ == '__main__':
	# Debugging, logging.

	if "DEBUG" in os.environ: app.debug = True

	if not app.debug:
		app.logger.addHandler(utils.create_syslog_handler())

	# Secret key.
	key_file = "/tmp/mailpile-multiplexer-key"
	try:
		import base64
		with open(key_file, "rb") as f:
			app.secret_key = base64.b64decode(f.read().strip())
	except IOError:
		# Generate a fresh secret key, invalidating any sessions.
		app.secret_key = os.urandom(24)
		with utils.create_file_with_mode(key_file, 0o640) as f:
			f.write(base64.b64encode(app.secret_key).decode('ascii') + "\n")

	# Start

	app.run(port=10223)

