#!/bin/bash
# rspamd spam filter setup for Mail-in-a-Box
# ============================================
#
# Alternative to SpamAssassin, selected via spam_filter setting in settings.yaml.
# rspamd provides:
#   - C multi-threaded scanning (scales to all CPUs)
#   - Built-in DNS resolver (fixes DNSBL blocked issues with bind9 forwarders)
#   - Redis-backed Bayes classifier (no file permission issues)
#   - Milter protocol integration with Postfix
#   - Web UI for monitoring on port 11334
#   - IMAPSieve-based learning via rspamc (no Perl/sa-learn overhead)
#
# This script is sourced from setup/spamassassin.sh when spam_filter=rspamd.

source setup/functions.sh
source /etc/mailinabox.conf

# Use MiaB venv python if available (has rtyaml), fallback to system python3
MIAB_PYTHON="/usr/local/lib/mailinabox/env/bin/python3"
if [ ! -x "$MIAB_PYTHON" ]; then
	MIAB_PYTHON="python3"
fi

echo "Installing rspamd spam filter..."

# === INSTALL PACKAGES ===

apt_install rspamd redis-server

# === WORKER CONFIGURATION ===

# Normal worker: scan mail using all available CPUs
NUM_CPUS=$(nproc)
cat > /etc/rspamd/local.d/worker-normal.inc << EOF
count = $NUM_CPUS;
EOF

# Proxy worker: milter mode for Postfix integration
cat > /etc/rspamd/local.d/worker-proxy.inc << 'EOF'
milter = yes;
timeout = 120s;
upstream "local" {
    self_scan = yes;
}
bind_socket = "127.0.0.1:11332";
count = 4;
EOF

# Controller worker: Web UI + API on port 11334
# Read rspamd_password from settings.yaml (simple grep, no Python needed)
RSPAMD_PASSWORD=$(cat "$STORAGE_ROOT/settings.yaml" 2>/dev/null | grep "^rspamd_password:" | awk '{print $2}')

# Auto-generate controller password if not set (needed for admin panel proxy)
if [ -z "$RSPAMD_PASSWORD" ]; then
	RSPAMD_PASSWORD=$(openssl rand -base64 24)
	# Persist to settings.yaml
	$MIAB_PYTHON << PYEOF
import sys, os
sys.path.insert(0, os.path.join('$PWD', 'management'))
from utils import load_settings, write_settings, load_environment
env = load_environment()
settings = load_settings(env)
settings['rspamd_password'] = '$RSPAMD_PASSWORD'
write_settings(settings, env)
PYEOF
fi

if [ -n "$RSPAMD_PASSWORD" ]; then
	RSPAMD_PASSWORD_HASH=$(rspamadm pw -p "$RSPAMD_PASSWORD" 2>/dev/null)
	cat > /etc/rspamd/local.d/worker-controller.inc << EOF
password = "$RSPAMD_PASSWORD_HASH";
bind_socket = "127.0.0.1:11334";
EOF
else
	cat > /etc/rspamd/local.d/worker-controller.inc << 'EOF'
bind_socket = "127.0.0.1:11334";
EOF
fi

# === BAYES CLASSIFIER (Redis backend) ===

cat > /etc/rspamd/local.d/classifier-bayes.conf << 'EOF'
backend = "redis";
servers = "127.0.0.1";
autolearn = true;
min_learns = 100;
EOF

# === REDIS CONFIGURATION ===

# Tune Redis for mail server use (memory limit, persistence)
tools/editconf.py /etc/redis/redis.conf -s \
	"bind=127.0.0.1 ::1" \
	"maxmemory=2gb" \
	"maxmemory-policy=allkeys-lru"

# === SCORING / ACTIONS ===

cat > /etc/rspamd/local.d/actions.conf << 'EOF'
reject = 15;
add_header = 5;
greylist = 4;
EOF

# === MILTER HEADERS ===
# Produce X-Spam-Status header compatible with existing Dovecot sieve rules
# that check: header :regex "X-Spam-Status" "^Yes"
# x-spamd-result: detailed per-symbol report (compatible with Thunderbird rspamd addons)
# x-spam-level: asterisk-based score visualization (like SpamAssassin X-Spam-Level)

cat > /etc/rspamd/local.d/milter_headers.conf << 'EOF'
use = ["x-spamd-bar", "x-spam-status", "x-spamd-result", "x-spam-level", "authentication-results"];
skip_local = false;
skip_authenticated = true;

routines {
  x-spam-status {
    header = "X-Spam-Status";
    remove = 1;
  }
  x-spamd-bar {
    header = "X-Spamd-Bar";
    positive = "+";
    negative = "-";
    neutral = "/";
    remove = 1;
  }
  x-spamd-result {
    header = "X-Spamd-Result";
    remove = 1;
  }
  x-spam-level {
    header = "X-Spam-Level";
    char = "*";
    remove = 1;
  }
  authentication-results {
    header = "Authentication-Results";
    remove = 0;
    add_smtp_user = false;
  }
}
EOF

# === DKIM SIGNING ===
# Keep OpenDKIM for DKIM signing (simpler migration). rspamd still validates
# DKIM on incoming mail. Disable rspamd's own signing to avoid conflicts.

cat > /etc/rspamd/local.d/dkim_signing.conf << 'EOF'
enabled = false;
EOF

# === PHISHING / URL CHECKS ===

cat > /etc/rspamd/local.d/phishing.conf << 'EOF'
openphish_enabled = true;
phishtank_enabled = true;
EOF

# === REPLIES MODULE ===
# Whitelist replies to messages sent from our server

cat > /etc/rspamd/local.d/replies.conf << 'EOF'
action = "no action";
expire = 86400;
EOF

# === MULTIMAP (whitelist/blacklist from settings.yaml) ===

WHITELIST_FILE="/etc/rspamd/local.d/whitelist-domains.map"
BLACKLIST_FILE="/etc/rspamd/local.d/blacklist-domains.map"
touch "$WHITELIST_FILE" "$BLACKLIST_FILE"

# Generate whitelist/blacklist map files from settings.yaml
$MIAB_PYTHON << PYEOF
import sys, os
sys.path.insert(0, os.path.join('$PWD', 'management'))
from utils import load_settings, load_environment
env = load_environment()
settings = load_settings(env)
wl = settings.get('spam_whitelist', [])
bl = settings.get('spam_blacklist', [])
with open('$WHITELIST_FILE', 'w') as f:
    f.write('\n'.join(wl) + '\n' if wl else '')
with open('$BLACKLIST_FILE', 'w') as f:
    f.write('\n'.join(bl) + '\n' if bl else '')
PYEOF

cat > /etc/rspamd/local.d/multimap.conf << EOF
WHITELIST_SENDER_DOMAIN {
    type = "from";
    map = "$WHITELIST_FILE";
    score = -10.0;
    description = "Whitelisted sender (MiaB admin)";
}

BLACKLIST_SENDER_DOMAIN {
    type = "from";
    map = "$BLACKLIST_FILE";
    score = 10.0;
    description = "Blacklisted sender (MiaB admin)";
}
EOF

# === DOVECOT IMAPSIEVE (learn spam/ham from user actions) ===
# When a user moves mail to/from Spam folder, train rspamd via rspamc

cat > /etc/dovecot/conf.d/90-imapsieve.conf << 'EOF'
protocol imap {
  mail_plugins = $mail_plugins imap_sieve
}

plugin {
  sieve_plugins = sieve_imapsieve sieve_extprograms
  sieve_global_extensions = +vnd.dovecot.pipe +vnd.dovecot.environment

  imapsieve_mailbox1_name = Spam
  imapsieve_mailbox1_causes = COPY APPEND
  imapsieve_mailbox1_before = file:/etc/dovecot/sieve/learn-spam.sieve

  imapsieve_mailbox2_name = *
  imapsieve_mailbox2_from = Spam
  imapsieve_mailbox2_causes = COPY
  imapsieve_mailbox2_before = file:/etc/dovecot/sieve/learn-ham.sieve

  sieve_pipe_bin_dir = /etc/dovecot/sieve
}
EOF

mkdir -p /etc/dovecot/sieve
# Sieve directory must be writable by the mail user so Dovecot can
# compile and cache .svbin binaries at runtime.
chown mail:dovecot /etc/dovecot/sieve
chmod 775 /etc/dovecot/sieve

# Dovecot's systemd unit uses ProtectSystem=full which mounts /etc read-only.
# We need an override to allow writing compiled sieve binaries.
mkdir -p /etc/systemd/system/dovecot.service.d
cat > /etc/systemd/system/dovecot.service.d/sieve-write.conf << 'EOF'
[Service]
ReadWritePaths=/etc/dovecot/sieve
EOF
systemctl daemon-reload

cat > /etc/dovecot/sieve/learn-spam.sieve << 'EOF'
require ["vnd.dovecot.pipe", "copy", "imapsieve", "environment", "variables"];
pipe :copy "rspamd-learn.sh" ["spam"];
EOF

cat > /etc/dovecot/sieve/learn-ham.sieve << 'EOF'
require ["vnd.dovecot.pipe", "copy", "imapsieve", "environment", "variables"];

# imap.mailbox = destination folder when moving FROM Spam.
# Skip learn_ham when user deletes spam (moves Spam -> Trash).
if environment :is "imap.mailbox" "Trash" {
    stop;
}

pipe :copy "rspamd-learn.sh" ["ham"];
EOF

# Learn script: lightweight rspamc call (no Perl overhead like sa-learn)
cat > /etc/dovecot/sieve/rspamd-learn.sh << 'LEARNEOF'
#!/bin/bash
# rspamd learning script for Dovecot IMAPSieve
# Called when users move messages to/from Spam folder
exec /usr/bin/rspamc learn_"$1"
LEARNEOF
chmod +x /etc/dovecot/sieve/rspamd-learn.sh

# Sieve scripts are compiled automatically by Dovecot at runtime when
# the sieve_extprograms and sieve_imapsieve plugins are loaded.
# Manual sievec compilation fails because it doesn't load these plugins.

# === REMOVE DEPRECATED DOVECOT ANTISPAM PLUGIN ===

# Remove antispam plugin from mail_plugins (used by SpamAssassin setup)
sed -i 's/ antispam//' /etc/dovecot/conf.d/20-imap.conf 2>/dev/null
sed -i 's/ antispam//' /etc/dovecot/conf.d/20-pop3.conf 2>/dev/null
# Remove the SpamAssassin-specific dovecot config
rm -f /etc/dovecot/conf.d/99-local-spampd.conf

# === DISABLE SPAMASSASSIN ===

systemctl stop spampd 2>/dev/null
systemctl disable spampd 2>/dev/null
systemctl stop spamassassin 2>/dev/null
systemctl disable spamassassin 2>/dev/null

# === INITIAL BAYES TRAINING ===
# Seed the Bayes classifier from existing mailboxes (ham from cur/, spam from .Spam/cur/)

if [ -d "$STORAGE_ROOT/mail/mailboxes" ]; then
	echo "Training rspamd Bayes from existing mailboxes..."
	# Ham: messages in cur/ directories (delivered and accepted by users)
	find "$STORAGE_ROOT/mail/mailboxes" -path "*/cur/*" -type f -print0 2>/dev/null | \
		head -z -n 5000 | xargs -0 -P4 -I{} rspamc learn_ham {} 2>/dev/null
	# Spam: messages in .Spam/cur/ directories (marked as spam by users)
	find "$STORAGE_ROOT/mail/mailboxes" -path "*/.Spam/cur/*" -type f -print0 2>/dev/null | \
		head -z -n 5000 | xargs -0 -P4 -I{} rspamc learn_spam {} 2>/dev/null
	echo "Bayes training complete."
fi

# === START SERVICES ===

restart_service redis-server
restart_service rspamd
restart_service dovecot
