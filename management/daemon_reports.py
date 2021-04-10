# -*- indent-tabs-mode: t; tab-width: 4; python-indent-offset: 4; -*-

import os
import logging
import json
import datetime
import time
import subprocess

log = logging.getLogger(__name__)

from flask import request, Response, session, redirect, jsonify, send_from_directory
from functools import wraps
from reporting.capture.db.SqliteConnFactory import SqliteConnFactory
import reporting.uidata as uidata

from mailconfig import ( get_mail_users, validate_email )

		
def add_reports(app, env, authorized_personnel_only):
	'''call this function to add reporting/sem endpoints

	`app` is a Flask instance
	`env` is the Mail-in-a-Box LDAP environment
	`authorized_personnel_only` is a flask wrapper from daemon.py
	ensuring only authenticated admins can access the endpoint

	'''

	CAPTURE_STORAGE_ROOT = os.environ.get(
		'CAPTURE_STORAGE_ROOT',
		os.path.join(env['STORAGE_ROOT'], 'reporting')
	)
	sqlite_file = os.path.join(CAPTURE_STORAGE_ROOT, 'capture.sqlite')
	db_conn_factory = SqliteConnFactory(sqlite_file)

	# UI support
	ui_dir = os.path.join(os.path.dirname(app.template_folder), 'reporting/ui')
	def send_ui_file(filename):
		return send_from_directory(ui_dir, filename)

	@app.route("/reports/ui/<path:filename>", methods=['GET'])
	def get_reporting_ui_file(filename):
		return send_ui_file(filename)
	
	@app.route('/reports')
	def reporting_redir():
		return redirect('/reports/')

	@app.route('/reports/', methods=['GET'])
	def reporting_main():
		return send_ui_file('index.html')


	# Decorator to unwrap json payloads. It returns the json as a dict
	# in named argument 'payload'
	def json_payload(func):
		@wraps(func)
		def wrapper(*args, **kwargs):
			try:
				log.debug('payload:%s', request.data)
				payload = json.loads(request.data)
				return func(*args, payload=payload, **kwargs)
			except json.decoder.JSONDecodeError as e:
				log.warning('Bad request: data:%s ex:%s', request.data, e)
				return ("Bad request", 400)
		return wrapper

	@app.route('/reports/uidata/messages-sent', methods=['POST'])
	@authorized_personnel_only
	@json_payload
	def get_data_chart_messages_sent(payload):
		conn = db_conn_factory.connect()
		try:
			return jsonify(uidata.messages_sent(conn, payload))
		except uidata.InvalidArgsError as e:
			return ('invalid request', 400)
		finally:
			db_conn_factory.close(conn)
			
	@app.route('/reports/uidata/messages-received', methods=['POST'])
	@authorized_personnel_only
	@json_payload
	def get_data_chart_messages_received(payload):
		conn = db_conn_factory.connect()
		try:
			return jsonify(uidata.messages_received(conn, payload))
		except uidata.InvalidArgsError as e:
			return ('invalid request', 400)
		finally:
			db_conn_factory.close(conn)
			
	@app.route('/reports/uidata/user-activity', methods=['POST'])
	@authorized_personnel_only
	@json_payload
	def get_data_user_activity(payload):
		conn = db_conn_factory.connect()
		try:
			return jsonify(uidata.user_activity(conn, payload))
		except uidata.InvalidArgsError as e:
			return ('invalid request', 400)
		finally:
			db_conn_factory.close(conn)

	@app.route('/reports/uidata/flagged-connections', methods=['POST'])
	@authorized_personnel_only
	@json_payload
	def get_data_flagged_connections(payload):
		conn = db_conn_factory.connect()
		try:
			return jsonify(uidata.flagged_connections(conn, payload))
		except uidata.InvalidArgsError as e:
			return ('invalid request', 400)
		finally:
			db_conn_factory.close(conn)

	@app.route('/reports/uidata/remote-sender-activity', methods=['POST'])
	@authorized_personnel_only
	@json_payload
	def get_data_remote_sender_activity(payload):
		conn = db_conn_factory.connect()
		try:
			return jsonify(uidata.remote_sender_activity(conn, payload))
		except uidata.InvalidArgsError as e:
			return ('invalid request', 400)
		finally:
			db_conn_factory.close(conn)

	@app.route('/reports/uidata/user-list', methods=['GET'])
	@authorized_personnel_only
	def get_data_user_list():
		return jsonify(get_mail_users(env, as_map=False))

	@app.route('/reports/uidata/select-list-suggestions', methods=['POST'])
	@authorized_personnel_only
	@json_payload
	def suggest(payload):
		conn = db_conn_factory.connect()
		try:
			return jsonify(uidata.select_list_suggestions(conn, payload))
		except uidata.InvalidArgsError as e:
			return ('invalid request', 400)
		finally:
			db_conn_factory.close(conn)
	
	@app.route('/reports/capture/config', methods=['GET'])
	@authorized_personnel_only
	def get_capture_config():
		try:
			with open("/var/run/mailinabox/runtime_config.json") as fp:
				return Response(fp.read(), mimetype="text/json")
		except FileNotFoundError:
			return jsonify({ 'status':'error', 'reason':'not running' })

	@app.route('/reports/capture/config', methods=['POST'])
	@authorized_personnel_only
	@json_payload
	def save_capture_config(payload):
		try:
			with open("/var/run/mailinabox/runtime_config.json") as fp:
				loc = json.loads(fp.read()).get('from', { 'type':'unknown' })
		except FileNotFoundError:
			return ('service is not running', 403)

		# loc: { type:'file', location:'<path>' }
		if loc.get('type') != 'file':
			return ('storage type is %s' % loc.get('type'), 403)

		log.warning('overwriting config file %s', loc['location'])

		# remove runtime-config extra fields that don't belong in
		# the user config
		if 'from' in payload:
			del payload['from']
			
		with open(loc['location'], "w") as fp:
			fp.write(json.dumps(payload, indent=4))

		r = subprocess.run(["systemctl", "reload", "miabldap-capture"])
		if r.returncode != 0:
			log.warning('systemctl reload failed for miabldap-capture: code=%s', r.returncode)
		else:
			# wait a sec for daemon to pick up new config
			# TODO: monitor runtime config for mtime change
			time.sleep(1)
			# invalidate stats cache. if prune policy changed, the stats
			# may be invalid
			uidata.clear_cache()
			
		return ("ok", 200)
	

	@app.route('/reports/capture/service/status', methods=['GET'])
	@authorized_personnel_only
	def get_capture_status():
		service = "miabldap-capture.service"

		if not os.path.exists("/etc/systemd/system/" + service):
			return jsonify([ 'not installed', 'not installed' ])
			
		r1 = subprocess.run(["systemctl", "is-active", "--quiet", service ])
		r2 = subprocess.run(["systemctl", "is-enabled", "--quiet", service ])
		
		return jsonify([
			'running' if r1.returncode == 0 else 'stopped',
			'enabled' if r2.returncode == 0 else 'disabled'
		])

	@app.route('/reports/capture/db/stats', methods=['GET'])
	@authorized_personnel_only
	def get_db_stats():
		conn = db_conn_factory.connect()
		try:
			return jsonify(uidata.capture_db_stats(conn))
		finally:
			db_conn_factory.close(conn)

	@app.route('/reports/uidata/message-headers', methods=['POST'])
	@authorized_personnel_only
	@json_payload
	def get_message_headers(payload):
		try:
			user_id = payload['user_id']
			lmtp_id = payload['lmtp_id']
		except KeyError:
			return ('invalid request', 400)

		if not validate_email(user_id, mode="user"):
			return ('invalid email address', 400)

		r = subprocess.run(
			[
				"/usr/bin/doveadm",
				"fetch",
				"-u",user_id,
				"hdr",
				"HEADER","received","LMTP id " + lmtp_id
			],
			encoding="utf8",
			stdout=subprocess.PIPE,
			stderr=subprocess.PIPE
		)
		
		if r.returncode != 0:
			log.error('retrieving message headers failed, code=%s, lmtp_id=%s, user_id=%s, stderr=%s', r.returncode, lmtp_id, user_id, r.stderr)
			return Response(r.stderr, status=400, mimetype='text/plain')

		else:
			out = r.stdout.strip()
			if out.startswith('hdr:\n'):
				out = out[5:]
			return Response(out, status=200, mimetype='text/plain')
		
		
