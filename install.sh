#!/usr/bin/env bash
set -euo pipefail

#############################################
# Digital Bot Installer (full)
# - Workdir prompt (or --workdir /path)
# - Separate REGISTRY vs PROJECT DOMAIN
# - Optional Docker registry login up front
# - Scaling prompts during install
# - Dynamic Caddy enable
# - Multi-node ready (external DB/MQ/Redis)
# - Backup helper (Postgres → ZIP → Telegram)
#############################################

BOLD='\033[1m'; RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
hdr(){ echo -e "\n${BOLD}${BLUE}═══════════════════════════════════════════════════════${NC}\n${BOLD}${BLUE}  $*${NC}\n${BOLD}${BLUE}═══════════════════════════════════════════════════════${NC}\n"; }
info(){ echo -e "${BLUE}[INFO]${NC} $*"; }
ok(){ echo -e "${GREEN}[SUCCESS]${NC} $*"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $*"; }
err(){ echo -e "${RED}[ERROR]${NC} $*"; }
# Strong password generator
gen_pw(){ LC_ALL=C tr -dc 'A-Za-z0-9!@#%^_+=' </dev/urandom | head -c ${1:-24}; echo; }

# ---------------- Workdir handling ----------------
DEFAULT_WORKDIR="/opt/digitalbot"
WORKDIR_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workdir) WORKDIR_ARG="${2:-}"; shift 2 ;;
    *) break ;;
  esac
done
choose_workdir(){
  hdr "Install / Run Directory"
  local dflt="$DEFAULT_WORKDIR" wd
  read -p "Install directory [${dflt}]: " wd; wd=${wd:-$dflt}
  sudo mkdir -p "$wd" 2>/dev/null || mkdir -p "$wd"
  if command -v sudo >/dev/null 2>&1; then sudo chown -R "$(id -u)":"$(id -g)" "$wd" 2>/dev/null || true; fi
  SCRIPT_DIR="$(cd "$wd" && pwd -P)"; export INSTALLER_WORKDIR="$SCRIPT_DIR"
}
if [[ -n "${WORKDIR_ARG:-}" ]]; then
  mkdir -p "$WORKDIR_ARG"; SCRIPT_DIR="$(cd "$WORKDIR_ARG" && pwd -P)"; export INSTALLER_WORKDIR="$SCRIPT_DIR"
elif [[ -n "${INSTALLER_WORKDIR:-}" ]]; then
  mkdir -p "$INSTALLER_WORKDIR"; SCRIPT_DIR="$(cd "$INSTALLER_WORKDIR" && pwd -P)"; export INSTALLER_WORKDIR="$SCRIPT_DIR"
else
  if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == /dev/fd/* || "${BASH_SOURCE[0]}" == /proc/* ]]; then
    choose_workdir
  else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"; export INSTALLER_WORKDIR="$SCRIPT_DIR"
  fi
fi

ENV_FILE="$SCRIPT_DIR/.env"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
CADDY_FILE="$SCRIPT_DIR/Caddyfile"
OPS_DIR="$SCRIPT_DIR/ops"; mkdir -p "$OPS_DIR"
BACKUP_SCRIPT="$OPS_DIR/backup.sh"

# ---------------- Prereqs ----------------
ensure_packages(){
  hdr "Prerequisites"
  if ! command -v curl >/dev/null 2>&1; then
    info "Installing curl & CA certificates…"; sudo apt-get update -y && sudo apt-get install -y curl ca-certificates
  fi
  if ! command -v docker >/dev/null 2>&1; then
    info "Installing Docker…"
    sudo apt-get update -y
    sudo apt-get install -y ca-certificates curl gnupg lsb-release
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    sudo apt-get update -y && sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo usermod -aG docker "$USER" || true
  fi
  if ! docker compose version >/dev/null 2>&1; then err "Docker Compose plugin not detected"; exit 1; fi
  ok "Prerequisites ready"
}

# ---------------- Backup old config ----------------
backup_existing(){
  if [[ -f "$ENV_FILE" || -f "$COMPOSE_FILE" || -f "$CADDY_FILE" ]]; then
    hdr "Backup existing config"
    local BACKUP_DIR="$SCRIPT_DIR/backup_$(date +%Y%m%d_%H%M%S)"; mkdir -p "$BACKUP_DIR"
    [[ -f "$ENV_FILE" ]] && cp "$ENV_FILE" "$BACKUP_DIR/.env"
    [[ -f "$COMPOSE_FILE" ]] && cp "$COMPOSE_FILE" "$BACKUP_DIR/docker-compose.yml"
    [[ -f "$CADDY_FILE" ]] && cp "$CADDY_FILE" "$BACKUP_DIR/Caddyfile"
    ok "Backed up to $BACKUP_DIR"
  fi
}

# ---------------- Registry login (optional) ----------------
registry_login_prompt(){
  hdr "Docker Registry"
  read -p "Use a PRIVATE registry? (y/N): " USE_REG; USE_REG=${USE_REG:-N}
  if [[ "$USE_REG" =~ ^[yY]$ ]]; then
    read -p "Registry URL (e.g. registry.example.com) [docker.io]: " REGISTRY_URL; REGISTRY_URL=${REGISTRY_URL:-docker.io}
    read -p "Registry username: " REG_USER
    read -s -p "Registry password: " REG_PASS; echo
    echo "$REG_PASS" | docker login "$REGISTRY_URL" -u "$REG_USER" --password-stdin
    ok "Logged in to $REGISTRY_URL"
  else
    REGISTRY_URL=""; REG_USER=""; REG_PASS=""
    info "Using public images or already-logged-in registry"
  fi
}

# ---------------- Collect config ----------------
collect_config(){
  hdr "Base Configuration"
  read -p "Project name [digitalbot]: " COMPOSE_PROJECT_NAME; COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME:-digitalbot}

  # Domains for app — separate from REGISTRY
  read -p "Main domain (e.g. example.com): " DOMAIN; [[ -z "$DOMAIN" ]] && { err "Domain required"; exit 1; }
  read -p "Client subdomain [client]: " CLIENT_SUB; CLIENT_SUB=${CLIENT_SUB:-client}
  CLIENT_APP_DOMAIN="$CLIENT_SUB.$DOMAIN"

  # Data placement
  hdr "Data Services on THIS node?"
  read -p "Install Postgres/RabbitMQ/Redis locally on THIS server? (Y/n): " LOC; LOC=${LOC:-Y}
  if [[ "$LOC" =~ ^[Yy]$ ]]; then
    RUN_LOCAL_DATA="y"
    POSTGRES_HOST="postgres"; RABBITMQ_HOST="rabbitmq"; REDIS_HOST="redis"
  else
    RUN_LOCAL_DATA="n"
    read -p "POSTGRES_HOST [postgres]: " POSTGRES_HOST; POSTGRES_HOST=${POSTGRES_HOST:-postgres}
    read -p "RABBITMQ_HOST [rabbitmq]: " RABBITMQ_HOST; RABBITMQ_HOST=${RABBITMQ_HOST:-rabbitmq}
    read -p "REDIS_HOST [redis]: " REDIS_HOST; REDIS_HOST=${REDIS_HOST:-redis}
  fi

  # Credentials with auto-strong defaults
  hdr "Credentials"
  read -p "Postgres user [postgres]: " POSTGRES_USER; POSTGRES_USER=${POSTGRES_USER:-postgres}
  local PG_PW_DEF="$(gen_pw 24)"
  read -s -p "Postgres password [auto:${PG_PW_DEF}]: " POSTGRES_PASSWORD; echo
  POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-$PG_PW_DEF}
  read -p "Postgres DB [digitalbot_db]: " POSTGRES_DB; POSTGRES_DB=${POSTGRES_DB:-digitalbot_db}

  read -p "RabbitMQ user [rabbit]: " RABBITMQ_USER; RABBITMQ_USER=${RABBITMQ_USER:-rabbit}
  local RB_PW_DEF="$(gen_pw 20)"
  read -s -p "RabbitMQ password [auto:${RB_PW_DEF}]: " RABBITMQ_PASSWORD; echo
  RABBITMQ_PASSWORD=${RABBITMQ_PASSWORD:-$RB_PW_DEF}

  local RD_PW_DEF="$(gen_pw 20)"
  read -s -p "Redis password [auto:${RD_PW_DEF}]: " REDIS_PASSWORD; echo
  REDIS_PASSWORD=${REDIS_PASSWORD:-$RD_PW_DEF}

  if [[ -n "${REGISTRY_URL:-}" && "$REGISTRY_URL" != "docker.io" ]]; then
    REG_PREFIX="${REGISTRY_URL}/"
  else
    REG_PREFIX=""
  fi

  # Images (don’t mix with DOMAIN)
  hdr "Images"
  read -p "Webapp image [${REG_PREFIX}digital-web:latest]: " WEBAPP_IMAGE; WEBAPP_IMAGE=${WEBAPP_IMAGE:-${REG_PREFIX}digital-web:latest}
  read -p "Client image [${REG_PREFIX}digital-client:latest]: " CLIENT_APP_IMAGE; CLIENT_APP_IMAGE=${CLIENT_APP_IMAGE:-${REG_PREFIX}digital-client:latest}
  read -p "Processor image [${REG_PREFIX}digital-processer:latest]: " PROCESSOR_IMAGE; PROCESSOR_IMAGE=${PROCESSOR_IMAGE:-${REG_PREFIX}digital-processer:latest}
  read -p "Worker image [${REG_PREFIX}digital-order-worker:latest]: " ORDER_WORKER_IMAGE; ORDER_WORKER_IMAGE=${ORDER_WORKER_IMAGE:-${REG_PREFIX}digital-order-worker:latest}
  read -p "Jobs image [${REG_PREFIX}digital-jobs:latest]: " JOBS_IMAGE; JOBS_IMAGE=${JOBS_IMAGE:-${REG_PREFIX}digital-jobs:latest}

  # Caddy
  hdr "Edge / Caddy"
  read -p "Enable Caddy on THIS node? (y/N): " ENABLE_CADDY; ENABLE_CADDY=${ENABLE_CADDY:-N}

  # Sizing with a SINGLE number
  hdr "Sizing / Autoscale (based on active users)"
  read -p "Active users at peak (concurrent) [10000]: " ACTIVE; ACTIVE=${ACTIVE:-10000}
  read -p "Avg requests per active user per minute [6]: " RPM_PER_USER; RPM_PER_USER=${RPM_PER_USER:-6}
  local RPS=$(( ACTIVE * RPM_PER_USER / 60 ))
  local need_mc=$(( RPS * 8 ))           # 8m per request (tunable)
  local web_repl=$(( (need_mc + 800) / 800 ))
  [[ $web_repl -lt 2 ]] && web_repl=2
  local proc_repl=$(( (ACTIVE/2000) + 1 ))
  local worker_repl=$(( (ACTIVE/3000) + 1 ))

  read -p "Webapp replicas [${web_repl}]: " WEB_REPL; WEB_REPL=${WEB_REPL:-$web_repl}
  read -p "Processor replicas [${proc_repl}]: " PROCESSER_REPLICAS; PROCESSER_REPLICAS=${PROCESSER_REPLICAS:-$proc_repl}
  read -p "Worker replicas [${worker_repl}]: " ORDER_WORKER_REPLICAS; ORDER_WORKER_REPLICAS=${ORDER_WORKER_REPLICAS:-$worker_repl}

  # Write .env
  hdr "Write .env"
  cat >"$ENV_FILE"<<EOF
COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME}

# Domains
DOMAIN=${DOMAIN}
CLIENT_APP_DOMAIN=${CLIENT_APP_DOMAIN}

# Images
WEBAPP_IMAGE=${WEBAPP_IMAGE}
CLIENT_APP_IMAGE=${CLIENT_APP_IMAGE}
PROCESSOR_IMAGE=${PROCESSOR_IMAGE}
ORDER_WORKER_IMAGE=${ORDER_WORKER_IMAGE}
JOBS_IMAGE=${JOBS_IMAGE}

# Data creds
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=${POSTGRES_DB}
RABBITMQ_USER=${RABBITMQ_USER}
RABBITMQ_PASSWORD=${RABBITMQ_PASSWORD}
REDIS_PASSWORD=${REDIS_PASSWORD}

# Hosts (multi-node)
POSTGRES_HOST=${POSTGRES_HOST}
RABBITMQ_HOST=${RABBITMQ_HOST}
REDIS_HOST=${REDIS_HOST}
RUN_LOCAL_DATA=${RUN_LOCAL_DATA}

# Caddy
ENABLE_CADDY=${ENABLE_CADDY}

# Replicas
WEBAPP_REPLICAS=${WEB_REPL}
PROCESSER_REPLICAS=${PROCESSER_REPLICAS}
ORDER_WORKER_REPLICAS=${ORDER_WORKER_REPLICAS}
EOF
  chmod 600 "$ENV_FILE"; ok ".env ready → $ENV_FILE"
}


# ---------------- Compose generator ----------------
generate_compose(){
  hdr "Generate docker-compose.yml"
  cat >"$COMPOSE_FILE"<<'EOF'
version: "3.9"
services:
  webapp:
    image: ${WEBAPP_IMAGE}
    restart: unless-stopped
    environment:
      - ConnectionStrings__DefaultConnection=Host=${POSTGRES_HOST};Database=${POSTGRES_DB};Username=${POSTGRES_USER};Password=${POSTGRES_PASSWORD}
      - RabbitMq__HOST=${RABBITMQ_HOST}
      - RabbitMq__Username=${RABBITMQ_USER}
      - RabbitMq__Password=${RABBITMQ_PASSWORD}
      - Redis__Host=${REDIS_HOST}
      - Redis__Password=${REDIS_PASSWORD}
      - ASPNETCORE_ENVIRONMENT=Production
    deploy:
      replicas: ${WEBAPP_REPLICAS}
      resources:
        limits: { cpus: "1.0", memory: "1024M" }
    networks: [ digitalbot_internal, digitalbot_web ]

  client-app:
    image: ${CLIENT_APP_IMAGE}
    restart: unless-stopped
    deploy:
      resources:
        limits: { cpus: "0.5", memory: "256M" }
    networks: [ digitalbot_web ]

  processor:
    image: ${PROCESSOR_IMAGE}
    restart: unless-stopped
    environment:
      - ConnectionStrings__DefaultConnection=Host=${POSTGRES_HOST};Database=${POSTGRES_DB};Username=${POSTGRES_USER};Password=${POSTGRES_PASSWORD}
      - RabbitMq__HOST=${RABBITMQ_HOST}
      - RabbitMq__Username=${RABBITMQ_USER}
      - RabbitMq__Password=${RABBITMQ_PASSWORD}
      - Redis__Host=${REDIS_HOST}
      - Redis__Password=${REDIS_PASSWORD}
      - ASPNETCORE_ENVIRONMENT=Production
    deploy:
      replicas: ${PROCESSER_REPLICAS}
      resources:
        limits: { cpus: "0.8", memory: "768M" }
    networks: [ digitalbot_internal ]

  worker:
    image: ${ORDER_WORKER_IMAGE}
    restart: unless-stopped
    environment:
      - ConnectionStrings__DefaultConnection=Host=${POSTGRES_HOST};Database=${POSTGRES_DB};Username=${POSTGRES_USER};Password=${POSTGRES_PASSWORD}
      - RabbitMq__HOST=${RABBITMQ_HOST}
      - RabbitMq__Username=${RABBITMQ_USER}
      - RabbitMq__Password=${RABBITMQ_PASSWORD}
      - Redis__Host=${REDIS_HOST}
      - Redis__Password=${REDIS_PASSWORD}
      - ASPNETCORE_ENVIRONMENT=Production
    deploy:
      replicas: ${ORDER_WORKER_REPLICAS}
    networks: [ digitalbot_internal ]

  jobs:
    image: ${JOBS_IMAGE}
    restart: unless-stopped
    environment:
      - ConnectionStrings__DefaultConnection=Host=${POSTGRES_HOST};Database=${POSTGRES_DB};Username=${POSTGRES_USER};Password=${POSTGRES_PASSWORD}
      - RabbitMq__HOST=${RABBITMQ_HOST}
      - RabbitMq__Username=${RABBITMQ_USER}
      - RabbitMq__Password=${RABBITMQ_PASSWORD}
      - Redis__Host=${REDIS_HOST}
      - Redis__Password=${REDIS_PASSWORD}
      - ASPNETCORE_ENVIRONMENT=Production
    networks: [ digitalbot_internal ]

  # Data services only when profile 'data' is enabled
  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB}
    volumes:
      - postgres-data:/var/lib/postgresql/data
    networks: [ digitalbot_internal ]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 6
    profiles: ["data"]

  rabbitmq:
    image: rabbitmq:3-management
    restart: unless-stopped
    environment:
      - RABBITMQ_DEFAULT_USER=${RABBITMQ_USER}
      - RABBITMQ_DEFAULT_PASS=${RABBITMQ_PASSWORD}
    networks: [ digitalbot_internal, digitalbot_web ]
    healthcheck:
      test: ["CMD", "rabbitmq-diagnostics", "status"]
      interval: 15s
      timeout: 5s
      retries: 5
    profiles: ["data"]

  redis:
    image: redis:7-alpine
    restart: unless-stopped
    command: ["redis-server", "--requirepass", "${REDIS_PASSWORD}"]
    networks: [ digitalbot_internal ]
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5
    profiles: ["data"]

  caddy:
    image: caddy:2
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy-data:/data
      - caddy-config:/config
    networks: [ digitalbot_web ]
    depends_on:
      - webapp
      - client-app
    profiles: ["caddy"]

volumes:
  postgres-data:
  caddy-data:
  caddy-config:

networks:
  digitalbot_web: {}
  digitalbot_internal:
    driver: bridge
    internal: true
EOF
  ok "docker-compose.yml → $COMPOSE_FILE"
}


# ---------------- Caddyfile ----------------
write_caddy(){
  if [[ "$(grep -E '^ENABLE_CADDY=' "$ENV_FILE" | cut -d= -f2)" =~ ^[yY]$ ]]; then
    hdr "Generate Caddyfile"
    # shellcheck disable=SC2016
    cat >"$CADDY_FILE"<<'EOF'
{$DOMAIN} {
  reverse_proxy webapp:8080 {
    header_up X-Real-IP {http.request.header.CF-Connecting-IP}
  }
}
{$CLIENT_APP_DOMAIN} {
  reverse_proxy client-app:80
}
EOF
    ok "Caddyfile → $CADDY_FILE"
  else
    warn "Caddy disabled"
  fi
}

# ---------------- Backup helper ----------------
write_backup_script(){
  cat >"$BACKUP_SCRIPT"<<'EOS'
#!/usr/bin/env bash
set -euo pipefail
ENV_FILE="$(dirname "$0")/../.env"; source "$ENV_FILE"
STAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="$(dirname "$0")/../backups"; mkdir -p "$OUTDIR"
FILE="${OUTDIR}/pg_${POSTGRES_DB}_${STAMP}.sql.gz"

echo "[INFO] dumping ${POSTGRES_DB}…"
docker compose -f "$(dirname "$0")/../docker-compose.yml" exec -T postgres \
  pg_dump -U "${POSTGRES_USER}" "${POSTGRES_DB}" | gzip > "$FILE"

echo "[OK] dump: $FILE"
if [[ "${TELEGRAM_BOT_TOKEN:-}" != "" && "${TELEGRAM_CHAT_ID:-}" != "" ]]; then
  echo "[INFO] sending to Telegram…"
  curl -fsS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
    -F "chat_id=${TELEGRAM_CHAT_ID}" \
    -F "document=@${FILE}" \
    -F "caption=DB backup ${STAMP}" >/dev/null
  echo "[OK] sent."
fi
EOS
  chmod +x "$BACKUP_SCRIPT"
}

configure_backup(){
  hdr "Backup setup"
  write_backup_script
  read -p "Enable Telegram delivery? (y/N): " T; T=${T:-N}
  if [[ "$T" =~ ^[yY]$ ]]; then
    read -p "TELEGRAM_BOT_TOKEN: " TB; read -p "TELEGRAM_CHAT_ID: " TC
    {
      grep -q '^TELEGRAM_BOT_TOKEN=' "$ENV_FILE" && sed -i "s|^TELEGRAM_BOT_TOKEN=.*|TELEGRAM_BOT_TOKEN=${TB}|" "$ENV_FILE" || echo "TELEGRAM_BOT_TOKEN=${TB}" >> "$ENV_FILE"
      grep -q '^TELEGRAM_CHAT_ID=' "$ENV_FILE" && sed -i "s|^TELEGRAM_CHAT_ID=.*|TELEGRAM_CHAT_ID=${TC}|" "$ENV_FILE" || echo "TELEGRAM_CHAT_ID=${TC}" >> "$ENV_FILE"
    }
  fi
  read -p "Create cron job (every 6h)? (y/N): " C; C=${C:-N}
  if [[ "$C" =~ ^[yY]$ ]]; then
    (crontab -l 2>/dev/null; echo "0 */6 * * * ${BACKUP_SCRIPT} >/dev/null 2>&1") | crontab -
    ok "Cron installed: every 6h"
  fi
}

# ---------------- Compose wrapper ----------------
compose_cmd(){
  local profiles=()
  if [[ -f "$ENV_FILE" ]]; then
    local en_caddy="$(grep -E '^ENABLE_CADDY=' "$ENV_FILE" | cut -d= -f2 || true)"
    local run_data="$(grep -E '^RUN_LOCAL_DATA=' "$ENV_FILE" | cut -d= -f2 || true)"
    [[ "$en_caddy" =~ ^[yY]$ ]] && profiles+=( --profile caddy )
    [[ "$run_data" =~ ^[yY]$ ]] && profiles+=( --profile data )
  fi
  docker compose -f "$COMPOSE_FILE" "${profiles[@]}" "$@"
}


# ---------------- Actions ----------------
do_install(){
  ensure_packages
  backup_existing
  registry_login_prompt
  collect_config
  generate_compose
  write_caddy
  hdr "Deploy"
  compose_cmd pull
  compose_cmd up -d
  ok "Stack up at $SCRIPT_DIR"
}

do_update(){ hdr "Update"; ensure_packages; compose_cmd pull; compose_cmd up -d; ok "Updated"; }

do_scale(){
  hdr "Scale"
  source "$ENV_FILE"
  read -p "Webapp replicas [${WEBAPP_REPLICAS:-2}]: " WR; WR=${WR:-${WEBAPP_REPLICAS:-2}}
  read -p "Processor replicas [${PROCESSER_REPLICAS:-2}]: " PR; PR=${PR:-${PROCESSER_REPLICAS:-2}}
  read -p "Worker replicas [${ORDER_WORKER_REPLICAS:-2}]: " OR; OR=${OR:-${ORDER_WORKER_REPLICAS:-2}}
  sed -i "s/^WEBAPP_REPLICAS=.*/WEBAPP_REPLICAS=${WR}/" "$ENV_FILE" || true
  sed -i "s/^PROCESSER_REPLICAS=.*/PROCESSER_REPLICAS=${PR}/" "$ENV_FILE" || true
  sed -i "s/^ORDER_WORKER_REPLICAS=.*/ORDER_WORKER_REPLICAS=${OR}/" "$ENV_FILE" || true
  compose_cmd up -d --scale webapp="$WR" --scale processor="$PR" --scale worker="$OR"
  ok "Scaled: webapp=${WR} processor=${PR} worker=${OR}"
}

do_registry(){ hdr "Registry login"; read -p "Registry URL [docker.io]: " R; R=${R:-docker.io}; read -p "Username: " U; read -s -p "Password: " P; echo; echo "$P" | docker login "$R" -u "$U" --password-stdin; ok "Logged in to $R"; }

# ---------------- Menu / CLI ----------------
show_menu(){
  hdr "Digital Bot Installer"
  cat <<MENU
Workdir: ${SCRIPT_DIR}

1) Install / Deploy (with prompts)
2) Update (pull + up)
3) Scale (change replicas)
4) Backup setup (PG → ZIP → Telegram)
5) Registry login
q) Quit
MENU
  read -p "Choice: " ch
  case "$ch" in
    1) do_install ;;
    2) do_update ;;
    3) do_scale ;;
    4) configure_backup ;;
    5) do_registry ;;
    q|Q) exit 0 ;;
    *) err "Invalid choice" ;;
  esac
}

case "${1:-}" in
  --install|install) shift || true; do_install ;;
  --update|update) shift || true; do_update ;;
  --scale|scale) shift || true; do_scale ;;
  --backup|backup) shift || true; configure_backup ;;
  --registry|registry) shift || true; do_registry ;;
  -h|--help) echo "Usage: $0 [--workdir /path] [--install|--update|--scale|--backup|--registry]"; exit 0 ;;
  *) show_menu ;;
esac
