#!/bin/bash
# rspamd spam filter setup for Mail-in-a-Box
# Sourced from setup/spamassassin.sh when spam_filter=rspamd.

source setup/functions.sh
source /etc/mailinabox.conf

# Use MiaB venv python if available, fallback to system python3
MIAB_PYTHON="/usr/local/lib/mailinabox/env/bin/python3"
if [ ! -x "$MIAB_PYTHON" ]; then
	MIAB_PYTHON="python3"
fi

echo "Installing rspamd spam filter..."

# === INSTALL PACKAGES ===

apt_install rspamd redis-server

# === WORKER CONFIGURATION ===

# Normal worker
NUM_CPUS=$(nproc)
cat > /etc/rspamd/local.d/worker-normal.inc << EOF
count = $NUM_CPUS;
EOF

# Proxy worker: milter mode for Postfix
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
RSPAMD_PASSWORD=$(cat "$STORAGE_ROOT/settings.yaml" 2>/dev/null | grep "^rspamd_password:" | awk '{print $2}')

# Auto-generate controller password if not set
if [ -z "$RSPAMD_PASSWORD" ]; then
	RSPAMD_PASSWORD=$(openssl rand -base64 24)
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

# === BAYES CLASSIFIER ===

cat > /etc/rspamd/local.d/classifier-bayes.conf << 'EOF'
backend = "redis";
servers = "127.0.0.1";
autolearn = true;
min_learns = 100;
EOF

# === REDIS CONFIGURATION ===

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
# X-Spam-Status compatible with existing Dovecot sieve rules

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
# Disable rspamd signing; OpenDKIM handles DKIM.

cat > /etc/rspamd/local.d/dkim_signing.conf << 'EOF'
enabled = false;
EOF

# === PHISHING / URL CHECKS ===

cat > /etc/rspamd/local.d/phishing.conf << 'EOF'
openphish_enabled = true;
phishtank_enabled = true;
EOF

# === REPLIES MODULE ===

cat > /etc/rspamd/local.d/replies.conf << 'EOF'
action = "no action";
expire = 86400;
EOF

# === MULTIMAP (whitelist/blacklist) ===

WHITELIST_FILE="/etc/rspamd/local.d/whitelist-domains.map"
BLACKLIST_FILE="/etc/rspamd/local.d/blacklist-domains.map"
touch "$WHITELIST_FILE" "$BLACKLIST_FILE"

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

# === DOVECOT IMAPSIEVE ===

# Add imap_sieve to 20-imap.conf (idempotent — only if not already present).
# Do NOT use a separate protocol imap {} block in 90-imapsieve.conf because
# Dovecot's last protocol block wins and would override 20-imap.conf plugins.
if ! grep -q 'imap_sieve' /etc/dovecot/conf.d/20-imap.conf 2>/dev/null; then
	sed -i 's/\(mail_plugins = .*imap_quota\)/\1 imap_sieve/' /etc/dovecot/conf.d/20-imap.conf
fi

cat > /etc/dovecot/conf.d/90-imapsieve.conf << 'EOF'
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

# Set correct ownership on 90-imapsieve.conf (rspamd.sh runs after mail-dovecot.sh chown)
chown mail:dovecot /etc/dovecot/conf.d/90-imapsieve.conf
chmod 640 /etc/dovecot/conf.d/90-imapsieve.conf

mkdir -p /etc/dovecot/sieve
# Writable so Dovecot can compile .svbin at runtime.
chown mail:dovecot /etc/dovecot/sieve
chmod 775 /etc/dovecot/sieve

# Override ProtectSystem=full to allow writing compiled sieve binaries.
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

# Learn script
cat > /etc/dovecot/sieve/rspamd-learn.sh << 'LEARNEOF'
#!/bin/bash
exec /usr/bin/rspamc learn_"$1"
LEARNEOF
chmod +x /etc/dovecot/sieve/rspamd-learn.sh


# === CLEANUP SPAMASSASSIN ARTIFACTS ===
sed -i 's/ antispam//' /etc/dovecot/conf.d/20-imap.conf 2>/dev/null
sed -i 's/ antispam//' /etc/dovecot/conf.d/20-pop3.conf 2>/dev/null
rm -f /etc/dovecot/conf.d/99-local-spampd.conf

# === DISABLE SPAMASSASSIN ===

systemctl stop spampd 2>/dev/null
systemctl disable spampd 2>/dev/null
systemctl stop spamassassin 2>/dev/null
systemctl disable spamassassin 2>/dev/null

# === INITIAL BAYES TRAINING ===

if [ -d "$STORAGE_ROOT/mail/mailboxes" ]; then
	echo "Training rspamd Bayes from existing mailboxes..."
	find "$STORAGE_ROOT/mail/mailboxes" -path "*/cur/*" -type f -print0 2>/dev/null | \
		head -z -n 5000 | xargs -0 -P4 -I{} rspamc learn_ham {} 2>/dev/null
	find "$STORAGE_ROOT/mail/mailboxes" -path "*/.Spam/cur/*" -type f -print0 2>/dev/null | \
		head -z -n 5000 | xargs -0 -P4 -I{} rspamc learn_spam {} 2>/dev/null
	echo "Bayes training complete."
fi

# === START SERVICES ===

restart_service redis-server
restart_service rspamd
restart_service dovecot
