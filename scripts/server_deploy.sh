#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# server_deploy.sh — deploy Way to Excellence to the wtexcel destination
# FROM the production server itself, reusing the secrets already present in the
# running container. Safe to re-run (idempotent). Intended for the 1.8 GB IONOS
# box, so it adds swap before the memory-heavy image build.
#
# Usage (as root, on the server):
#   cd /root && rm -rf wtdeploy \
#     && git clone -b claude/determined-euler-gkr9sv https://github.com/augaish/wtexcellence.git wtdeploy \
#     && cd wtdeploy && bash scripts/server_deploy.sh
# ---------------------------------------------------------------------------
set -euo pipefail

DEST=wtexcel
SERVER_IP=74.208.192.18
WEB_FILTER=wtexcel-web

banner() { echo; echo "=====> $*"; }

# --- 1. Swap (build needs more RAM than this box has) ----------------------
banner "1/7 Ensuring swap exists"
if [ "$(cat /proc/sys/vm/swappiness 2>/dev/null; free -b | awk '/Swap/{print $2}')" = "0" ] || [ "$(free -b | awk '/Swap/{print $2}')" -lt 1073741824 ]; then
  if [ ! -f /swapfile ]; then
    echo "Creating 4G /swapfile ..."
    fallocate -l 4G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=4096
    chmod 600 /swapfile
    mkswap /swapfile
  fi
  swapon /swapfile 2>/dev/null || true
  grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi
free -h | awk '/Mem|Swap/'

# --- 2. Install kamal 2.8.1 (via Ruby) if missing --------------------------
banner "2/7 Ensuring kamal 2.8.1 is installed"
if ! command -v kamal >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq ruby ruby-dev build-essential git curl >/dev/null
  gem install kamal -v 2.8.1 --no-document
fi
kamal version

# --- 3. Locate the running web container -----------------------------------
banner "3/7 Reading secrets from the running container (stays on this server)"
CID=$(docker ps --filter "name=${WEB_FILTER}" -q | head -1)
if [ -z "$CID" ]; then echo "ERROR: no running ${WEB_FILTER} container found"; exit 1; fi
echo "Container: $CID"

# Pull the live env (null-delimited so values with special chars survive).
declare -A CENV
while IFS= read -r -d '' kv; do CENV[${kv%%=*}]=${kv#*=}; done < <(docker exec "$CID" env -0)

# Map the 6 PROD secrets to the WTEXCEL_-prefixed names secrets.wtexcel expects.
for n in RAILS_MASTER_KEY SECRET_KEY_BASE POSTGRES_PASSWORD REDIS_PASSWORD DATABASE_URL REDIS_URL; do
  export "WTEXCEL_${n}=${CENV[$n]-}"
done
# Pass the rest through under their own names.
for n in OPENROUTER_API_KEY OPENROUTER_MODEL OLLAMA_URL SENTRY_DSN \
         CAPA_ACTION_PROVIDER CAPA_CLAUSE_PROVIDER CAPA_QUESTIONNAIRE_PROVIDER \
         CAPA_ACTION_OLLAMA_MODEL CAPA_CLAUSE_OLLAMA_MODEL CAPA_QUESTIONNAIRE_OLLAMA_MODEL \
         CAPA_QUESTIONNAIRE_SINGLE_PAIR_OLLAMA_MODEL CAPA_ROOT_CAUSE_OLLAMA_MODEL \
         SMTP_PORT SMTP_SERVER SMTP_LOGIN SMTP_PASSWORD SMTP_DOMAIN; do
  # A value given on the command line wins over the one carried forward from
  # the running container, so a setting can be added or changed at deploy:
  #   SMTP_SERVER=smtp.mailersend.net SMTP_LOGIN=... bash scripts/server_deploy.sh
  # Later deploys carry it forward from the container automatically.
  export "${n}=${!n:-${CENV[$n]-}}"
done
: "${OPENROUTER_MODEL:=anthropic/claude-sonnet-4.5}"
export OPENROUTER_MODEL
echo "Secrets loaded: RAILS_MASTER_KEY=${WTEXCEL_RAILS_MASTER_KEY:+ok} DATABASE_URL=${WTEXCEL_DATABASE_URL:+ok} OPENROUTER_API_KEY=${OPENROUTER_API_KEY:+ok} SMTP_SERVER=${SMTP_SERVER:+ok} SMTP_LOGIN=${SMTP_LOGIN:+ok} SMTP_PASSWORD=${SMTP_PASSWORD:+ok}"
# Emails (invitations, password resets) go through SMTP; without these they are silently lost.
if [ -z "${SMTP_SERVER}" ] || [ -z "${SMTP_LOGIN}" ] || [ -z "${SMTP_PASSWORD}" ]; then
  echo "WARNING: SMTP_SERVER / SMTP_LOGIN / SMTP_PASSWORD are not all set — no email will be delivered." >&2
fi

# --- 4. Registry password (from docker login on this box) -------------------
banner "4/7 Recovering Docker registry password"
REGPASS=$(python3 - <<'PY' 2>/dev/null || true
import json, base64, os
p = os.path.expanduser("/root/.docker/config.json")
try:
    c = json.load(open(p))
except Exception:
    raise SystemExit
for k, v in (c.get("auths") or {}).items():
    a = v.get("auth")
    if a:
        try:
            u, pw = base64.b64decode(a).decode().split(":", 1)
        except Exception:
            continue
        if u == "augaishb" or "docker.io" in k:
            print(pw); break
PY
)
if [ -z "${REGPASS:-}" ]; then
  echo "Could not auto-recover the registry password from /root/.docker/config.json."
  read -rs -p "Enter the Docker Hub password for user 'augaishb': " REGPASS; echo
fi
export WTEXCEL_KAMAL_REGISTRY_PASSWORD="$REGPASS"
echo "Registry password: ${WTEXCEL_KAMAL_REGISTRY_PASSWORD:+ok}"

# --- 5. SSH self-access (kamal connects to the server as root@IP) -----------
banner "5/7 Ensuring root can SSH to ${SERVER_IP} (itself)"
mkdir -p /root/.ssh && chmod 700 /root/.ssh
[ -f /root/.ssh/id_ed25519 ] || ssh-keygen -t ed25519 -N '' -f /root/.ssh/id_ed25519 -q
touch /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys
grep -qxF "$(cat /root/.ssh/id_ed25519.pub)" /root/.ssh/authorized_keys || cat /root/.ssh/id_ed25519.pub >> /root/.ssh/authorized_keys
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes "root@${SERVER_IP}" true && echo "self-ssh ok"

# --- 6. Show what we're about to deploy ------------------------------------
banner "6/7 Deploying commit"
git -C "$(dirname "$0")/.." log --oneline -1 || true

# --- 7. Deploy --------------------------------------------------------------
banner "7/7 kamal deploy -d ${DEST}  (this builds the image — can take 20-40 min)"
kamal deploy -d "${DEST}"

banner "DONE. Verify:"
echo "kamal app exec -d ${DEST} --reuse \"bin/rails 'ingestion:test_pdf[KAQA]'\""
