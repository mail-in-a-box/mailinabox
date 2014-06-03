#!/usr/bin/python3

import os, os.path

from flask import Flask, request, render_template
app = Flask(__name__)

import utils
from mailconfig import get_mail_users, add_mail_user, set_mail_password, remove_mail_user, get_mail_aliases, get_mail_domains, add_mail_alias, remove_mail_alias

env = utils.load_environment()

@app.route('/')
def index():
    return render_template('index.html')

# MAIL

@app.route('/mail/users')
def mail_users():
    return "".join(x+"\n" for x in get_mail_users(env))

@app.route('/mail/users/add', methods=['POST'])
def mail_users_add():
	return add_mail_user(request.form.get('email', ''), request.form.get('password', ''), env)

@app.route('/mail/users/password', methods=['POST'])
def mail_users_password():
	return set_mail_password(request.form.get('email', ''), request.form.get('password', ''), env)

@app.route('/mail/users/remove', methods=['POST'])
def mail_users_remove():
	return remove_mail_user(request.form.get('email', ''), env)

@app.route('/mail/aliases')
def mail_aliases():
    return "".join(x+"\t"+y+"\n" for x, y in get_mail_aliases(env))

@app.route('/mail/aliases/add', methods=['POST'])
def mail_aliases_add():
	return add_mail_alias(request.form.get('source', ''), request.form.get('destination', ''), env)

@app.route('/mail/aliases/remove', methods=['POST'])
def mail_aliases_remove():
	return remove_mail_alias(request.form.get('source', ''), env)

@app.route('/mail/domains')
def mail_domains():
    return "".join(x+"\n" for x in get_mail_domains(env))

# DNS

@app.route('/dns/update', methods=['POST'])
def dns_update():
	from dns_update import do_dns_update
	return do_dns_update(env)

# APP

if __name__ == '__main__':
	if "DEBUG" in os.environ: app.debug = True
	app.run(port=10222)
