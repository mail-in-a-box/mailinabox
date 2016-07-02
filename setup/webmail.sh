#!/bin/bash
# Webmail with Roundcube
# ----------------------

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

# ### Installing Rainloop

# Rainloop's webpage (http://www.rainloop.net/downloads/) does not easily	#
# list versions as the need for VERSION_FILENAME below. 			#

# 
# Dependancies are from Roundcube, not all may be needed for Rainloop		#

echo "Installing Rainloop (webmail)..."
apt_install \
	dbconfig-common \
	unzip \
	php5 php5-sqlite php5-mcrypt php5-intl php5-json php5-common php-auth php-net-smtp php-net-socket php-net-sieve php-mail-mime php-crypt-gpg php5-gd php5-pspell \
	tinymce libjs-jquery libjs-jquery-mousewheel libmagic1
apt_get_quiet remove php-mail-mimedecode # no longer needed since Roundcube 1.1.3

# We used to install Roundcube from Ubuntu, without triggering the dependencies #NODOC
# on Apache and MySQL, by downloading the debs and installing them manually. #NODOC
# Now that we're beyond that, get rid of those debs before installing from source. #NODOC
apt-get purge -qq -y roundcube* #NODOC

# Install Roundcube from source if it is not already present or if it is out of date.
# Combine the Roundcube version number with the commit hash of vacation_sieve to track
# whether we have the latest version.
VERSION=v1.10.1.127
VERSION_FILENAME="rainloop-community-1.10.1.127-18d553ae9cd96eb102059b04fdee62e0.zip"
HASH=bf2b42c99a6d8be151e2c1dc3442604ca709e1ba
UPDATE_KEY=$VERSION
needs_update=0 #NODOC
if [ ! -f /usr/local/lib/rainloop/version ]; then
	# not installed yet #NODOC
	needs_update=1 #NODOC
elif [[ "$UPDATE_KEY" != "$(cat /usr/local/lib/rainloop/version)" ]]; then
	# checks if the version is what we want
	needs_update=1 #NODOC
fi
if [ $needs_update == 1 ]; then
	# install rainloop
	wget_verify \
		https://github.com/RainLoop/rainloop-webmail/releases/download/$VERSION/$VERSION_FILENAME \
		$HASH \
		/tmp/rainloop.zip
	# Per documentation, updates can overwrite existing files
	unzip -q -o /tmp/rainloop.zip -d /usr/local/lib/rainloop
	rm -f /tmp/rainloop.zip


	# record the version we've installed
	echo $UPDATE_KEY > /usr/local/lib/rainloop/version
fi

# ### Configuring Rainloop

# Creating configs.
#
# Rainloop has a default password set, not sure yet how to integrate with imap userlist
# for now we should change it from the default
# Methods for changing password: https://github.com/RainLoop/rainloop-webmail/issues/28
#
# Untested: edit admin_password = "????" below
#
#	or use the Rainloop API:
#	<?php
#
#	$_ENV['RAINLOOP_INCLUDE_AS_API'] = true;
#	include '<path-to-rainloop-folder>/index.php';
#
#	$oConfig = \RainLoop\Api::Config();
#	$oConfig->SetPassword('pa$$wOrd');
#	echo $oConfig->Save() ? 'Done' : 'Error';
#
#	?>

# This can be improved, need to take a look at editconf.py for multi line edits as
# there are multiple "enable = On" but we should only edit them per category.

# Some application paths are not created until the application is launched
# workaround by making paths for our configs

mkdir -p /usr/local/lib/rainloop/data/_data_/_default_/configs/
cat > /usr/local/lib/rainloop/data/_data_/_default_/configs/application.ini <<EOF;
; RainLoop Webmail configuration file
; Please don't add custom parameters here, those will be overwritten

[webmail]
; Text displayed as page title
title = "RainLoop Webmail"

; Text displayed on startup
loading_description = "RainLoop"
favicon_url = ""

; Theme used by default
theme = "Default"

; Allow theme selection on settings screen
allow_themes = On
allow_user_background = Off

; Language used by default
language = "en"

; Admin Panel interface language
language_admin = "en"

; Allow language selection on settings screen
allow_languages_on_settings = On
allow_additional_accounts = On
allow_additional_identities = On

;  Number of messages displayed on page by default
messages_per_page = 20

; File size limit (MB) for file upload on compose screen
; 0 for unlimited.
attachment_size_limit = 25

[interface]
show_attachment_thumbnail = On
use_native_scrollbars = Off

[branding]
login_logo = ""
login_background = ""
login_desc = ""
login_css = ""
login_powered = On
user_css = ""
user_logo = ""
user_logo_title = ""
user_logo_message = ""
user_iframe_message = ""
welcome_page_url = ""
welcome_page_display = "none"

[contacts]
; Enable contacts
enable = On
allow_sharing = On
allow_sync = On
sync_interval = 20
type = "sqlite"
pdo_dsn = "mysql:host=127.0.0.1;port=3306;dbname=rainloop"
pdo_user = "root"
pdo_password = ""
suggestions_limit = 30

[security]
; Enable CSRF protection (http://en.wikipedia.org/wiki/Cross-site_request_forgery)
csrf_protection = On
custom_server_signature = "RainLoop"
x_frame_options_header = ""
openpgp = Off
openpgp_public_key_server = ""
use_rsa_encryption = Off

; Login and password for web admin panel
admin_login = "admin"
admin_password = "$(openssl rand -base64 8)"

; Access settings
allow_admin_panel = On
allow_two_factor_auth = Off
force_two_factor_auth = Off
admin_panel_host = ""
admin_panel_key = "admin"
content_security_policy = ""
core_install_access_domain = ""

[ssl]
; Require verification of SSL certificate used.
verify_certificate = Off

; Allow self-signed certificates. Requires verify_certificate.
allow_self_signed = On

; Location of Certificate Authority file on local filesystem (/etc/ssl/certs/ca-certificates.crt)
cafile = ""

; capath must be a correctly hashed certificate directory. (/etc/ssl/certs/)
capath = ""

[capa]
folders = On
composer = On
contacts = On
settings = On
quota = On
help = On
reload = On
search = On
search_adv = On
filters = On
x-templates = Off
dangerous_actions = On
message_actions = On
messagelist_actions = On
attachments_actions = On

[login]
default_domain = "$PRIMARY_HOSTNAME"

; Allow language selection on webmail login screen
allow_languages_on_login = On
determine_user_language = On
determine_user_domain = Off
welcome_page = Off
forgot_password_link_url = ""
registration_link_url = ""

; This option allows webmail to remember the logged in user
; once they closed the browser window.
; 
; Values:
;   "DefaultOff" - can be used, disabled by default;
;   "DefaultOn"  - can be used, enabled by default;
;   "Unused"     - cannot be used
sign_me_auto = "DefaultOff"

[plugins]
; Enable plugin support
enable = Off

; List of enabled plugins
enabled_list = ""

[defaults]
; Editor mode used by default (Plain, Html, HtmlForced or PlainForced)
view_editor_type = "Html"

; layout: 0 - no preview, 1 - side preview, 2 - bottom preview
view_layout = 1
view_use_checkboxes = On
autologout = 30
show_images = Off
contacts_autosave = On
mail_use_threads = Off
mail_reply_same_folder = Off

[logs]
; Enable logging
enable = Off

; Logs entire request only if error occured (php requred)
write_on_error_only = Off

; Logs entire request only if php error occured
write_on_php_error_only = Off

; Logs entire request only if request timeout (in seconds) occured.
write_on_timeout_only = 0

; Required for development purposes only.
; Disabling this option is not recommended.
hide_passwords = On
time_offset = 0
session_filter = ""

; Log filename.
; For security reasons, some characters are removed from filename.
; Allows for pattern-based folder creation (see examples below).
; 
; Patterns:
;   {date:Y-m-d}  - Replaced by pattern-based date
;                   Detailed info: http://www.php.net/manual/en/function.date.php
;   {user:email}  - Replaced by user's email address
;                   If user is not logged in, value is set to "unknown"
;   {user:login}  - Replaced by user's login (the user part of an email)
;                   If user is not logged in, value is set to "unknown"
;   {user:domain} - Replaced by user's domain name (the domain part of an email)
;                   If user is not logged in, value is set to "unknown"
;   {user:uid}    - Replaced by user's UID regardless of account currently used
; 
;   {user:ip}
;   {request:ip}  - Replaced by user's IP address
; 
; Others:
;   {imap:login} {imap:host} {imap:port}
;   {smtp:login} {smtp:host} {smtp:port}
; 
; Examples:
;   filename = "log-{date:Y-m-d}.txt"
;   filename = "{date:Y-m-d}/{user:domain}/{user:email}_{user:uid}.log"
;   filename = "{user:email}-{date:Y-m-d}.txt"
filename = "log-{date:Y-m-d}.txt"

; Enable auth logging in a separate file (for fail2ban)
auth_logging = Off
auth_logging_filename = "fail2ban/auth-{date:Y-m-d}.txt"
auth_logging_format = "[{date:Y-m-d H:i:s}] Auth failed: ip={request:ip} user={imap:login} host={imap:host} port={imap:port}"

[debug]
; Special option required for development purposes
enable = Off

[social]
; Google
google_enable = Off
google_enable_auth = Off
google_enable_auth_fast = Off
google_enable_drive = Off
google_enable_preview = Off
google_client_id = ""
google_client_secret = ""
google_api_key = ""

; Facebook
fb_enable = Off
fb_app_id = ""
fb_app_secret = ""

; Twitter
twitter_enable = Off
twitter_consumer_key = ""
twitter_consumer_secret = ""

; Dropbox
dropbox_enable = Off
dropbox_api_key = ""

[cache]
; The section controls caching of the entire application.
; 
; Enables caching in the system
enable = On

; Additional caching key. If changed, cache is purged
index = "v1"

; Can be: files, APC, memcache, redis (beta)
fast_cache_driver = "files"

; Additional caching key. If changed, fast cache is purged
fast_cache_index = "v1"

; Browser-level cache. If enabled, caching is maintainted without using files
http = On

; Caching message UIDs when searching and sorting (threading)
server_uids = On

[labs]
; Experimental settings. Handle with care.
; 
allow_mobile_version = On
ignore_folders_subscription = Off
check_new_password_strength = On
update_channel = "stable"
allow_gravatar = On
allow_prefetch = On
allow_smart_html_links = On
cache_system_data = On
date_from_headers = Off
autocreate_system_folders = On
allow_message_append = Off
disable_iconv_if_mbstring_supported = Off
login_fault_delay = 1
log_ajax_response_write_limit = 300
allow_html_editor_source_button = Off
allow_html_editor_biti_buttons = Off
allow_ctrl_enter_on_compose = Off
try_to_detect_hidden_images = Off
hide_dangerous_actions = Off
use_app_debug_js = Off
use_app_debug_css = Off
use_imap_sort = On
use_imap_force_selection = Off
use_imap_list_subscribe = On
use_imap_thread = On
use_imap_move = Off
use_imap_expunge_all_on_delete = Off
imap_forwarded_flag = "$Forwarded"
imap_read_receipt_flag = "$ReadReceipt"
imap_body_text_limit = 555000
imap_message_list_fast_simple_search = On
imap_message_list_count_limit_trigger = 0
imap_message_list_date_filter = 0
imap_message_list_permanent_filter = ""
imap_message_all_headers = Off
imap_large_thread_limit = 50
imap_folder_list_limit = 200
imap_show_login_alert = On
imap_use_auth_plain = On
imap_use_auth_cram_md5 = On
smtp_show_server_errors = Off
smtp_use_auth_plain = On
smtp_use_auth_cram_md5 = On
sieve_allow_raw_script = Off
sieve_utf8_folder_name = On
imap_timeout = 300
smtp_timeout = 60
sieve_timeout = 10
domain_list_limit = 99
mail_func_clear_headers = On
mail_func_additional_parameters = Off
favicon_status = On
folders_spec_limit = 50
owncloud_save_folder = "Attachments"
curl_proxy = ""
curl_proxy_auth = ""
in_iframe = Off
force_https = Off
custom_login_link = ""
custom_logout_link = ""
allow_external_login = Off
allow_external_sso = Off
external_sso_key = ""
http_client_ip_check_proxy = Off
fast_cache_memcache_host = "127.0.0.1"
fast_cache_memcache_port = 11211
fast_cache_redis_host = "127.0.0.1"
fast_cache_redis_port = 6379
use_local_proxy_for_external_images = Off
detect_image_exif_orientation = On
cookie_default_path = ""
cookie_default_secure = Off
replace_env_in_configuration = ""
startup_url = ""
emogrifier = On
dev_email = ""
dev_password = ""

[version]
current = "1.10.1.127"
saved = "Fri, 01 Jul 2016 03:41:58 +0000"
EOF

# Add localhost imap/smtp
mkdir -p /usr/local/lib/rainloop/data/_data_/_default_/domains/
cat > /usr/local/lib/rainloop/data/_data_/_default_/domains/default.ini <<EOF;
imap_host = "127.0.0.1"
imap_port = 993
imap_secure = "SSL"
imap_short_login = Off
sieve_use = On
sieve_allow_raw = Off
sieve_host = "127.0.0.1"
sieve_port = 4190
sieve_secure = "None"
smtp_host = "127.0.0.1"
smtp_port = 587
smtp_secure = "TLS"
smtp_short_login = Off
smtp_auth = On
smtp_php_mail = Off
EOF

# Fix permissions after editing configs

find /usr/local/lib/rainloop -type d -exec chmod 755 {} \;
find /usr/local/lib/rainloop -type f -exec chmod 644 {} \;
chown -R www-data:www-data /usr/local/lib/rainloop

# Enable PHP modules.
php5enmod mcrypt
restart_service php5-fpm

# remove Roundcube
# rm -rf /usr/local/lib/roundcube
