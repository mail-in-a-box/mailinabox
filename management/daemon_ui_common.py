# -*- indent-tabs-mode: t; tab-width: 4; python-indent-offset: 4; -*-

import os
import logging
import json
import datetime

# setup our root logger - named so oauth/*.py files become children
log = logging.getLogger(__name__)

from flask import request, session, redirect, jsonify, send_from_directory


		
def add_ui_common(app):
	'''
	call this function to add an endpoint that delivers common ui files

	`app` is a Flask instance
	'''

	# UI support
	ui_dir = os.path.join(os.path.dirname(app.template_folder), 'ui-common')
	def send_ui_file(filename):
		return send_from_directory(ui_dir, filename)

	@app.route("/ui-common/<path:filename>", methods=['GET'])
	def get_common_ui_file(filename):
		return send_ui_file(filename)
	
		
