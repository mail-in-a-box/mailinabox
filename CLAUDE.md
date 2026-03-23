# mailinabox — Fork Mail-in-a-Box (geseidl-edition)

> **Parent:** [../CLAUDE.md](../CLAUDE.md) (Gestime Ecosystem — reguli universale)

---

## Overview

Fork Mail-in-a-Box cu customizări pentru mediul Geseidl (NAT, DNS extern, rspamd, arhivare email).

| Aspect | Detalii |
|--------|---------|
| **Repo** | robertpopa22/mailinabox (fork upstream mail-in-a-box/mailinabox) |
| **Branch integrat** | `geseidl-edition` (combină toate feature-urile) |
| **Deploy** | MAIL02 (10.0.1.89), Hyper-V pe GES-S00 |
| **SSH** | `ssh -i ~/.ssh/ges-mail01 dit2022@10.0.1.89` |
| **Resurse** | 56 vCPU, 64 GB RAM |

---

## Feature Branches

Fiecare branch e independent, de pe `main`:

| Branch | Scop |
|--------|------|
| `feature/external-dns-settings` | Skip NS/DNSSEC/TLSA/glue/A record checks pt DNS extern (Cloudflare) |
| `feature/nat-aware-checks` | Service checks pe PRIVATE_IP când behind NAT, MTA-STS fallback localhost |
| `feature/spamhaus-forwarders-fix` | Auto zone exception pt spamhaus.org când bind9 are forwarders |
| `feature/email-archive-option` | `archive_address` în settings.yaml → `always_bcc` în Postfix |
| `feature/rspamd-spam-filter` | Înlocuire SpamAssassin cu rspamd |
| `feature/whitelist-management` | API admin whitelist/blacklist (ambele filtre) |
| `feature/rspamd-hardening` | DQS, composite rules, DMARC scoring, Lua anti-phishing |

---

## API Endpoints

| Endpoint | Scop |
|----------|------|
| `/admin/system/external-dns` | Configurare DNS extern |
| `/admin/system/nat-mode` | Configurare NAT mode |
| `/admin/system/archive` | Configurare arhivare email |
| `/admin/system/spam-filter` | Switch SA/rspamd |
| `/admin/system/spam-whitelist` | Whitelist/blacklist management |

---

## Configurare

- Settings în `$STORAGE_ROOT/settings.yaml` (citit cu `utils.load_settings(env)`)
- Env vars MiaB: `PUBLIC_IP`, `PRIVATE_IP`, `PRIMARY_HOSTNAME`, `STORAGE_ROOT` din `/etc/mailinabox.conf`
- Spamhaus DQS key: configurată pe MAIL02
- Status actual: rspamd ACTIV, SpamAssassin DEZACTIVAT

---

## Reguli

- **Testează pe MAIL02** înainte de merge în `geseidl-edition`
- Feature branches rămân independente — merge doar în `geseidl-edition`, nu între ele
- Verifică `NET-ADMIN/GESEIDL/` pentru detalii infrastructură MAIL02
