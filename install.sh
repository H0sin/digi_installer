#!/usr/bin/env bash
set -euo pipefail

# ============== UI helpers ==============
BOLD='\033[1m'; RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
hdr(){ echo -e "\n${BOLD}${BLUE}═══════════════════════════════════════════════════════${NC}\n${BOLD}${BLUE}  $*${NC}\n${BOLD}${BLUE}═══════════════════════════════════════════════════════${NC}\n"; }
info(){ echo -e "${BLUE}[INFO]${NC} $*"; }
ok(){ echo -e "${GREEN}[SUCCESS]${NC} $*"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $*"; }
err(){ echo -e "${RED}[ERROR]${NC} $*"; }

# ============== Workdir handling (supports bash <(curl …)) ==============
DEFAULT_WORKDIR="/opt/digitalbot"
WORKDIR_ARG=""
# allow leading --workdir before command verb (e.g., --install)
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workdir) WORKDIR_ARG="${2:-}"; shift 2 ;;
    *) break ;;
  esac
done

choose_workdir() {
  hdr "Install / Run Directory"
  local dflt="${DEFAULT_WORKDIR}" wd
  read -p "Install directory [${dflt}]: " wd
  wd=${wd:-$dflt}
  sudo mkdir -p "$wd" 2>/dev/null || mkdir -p "$wd"
  if command -v sudo >/dev/null 2>&1; then sudo chown -R "$(id -u)":"$(id -g)" "$wd" 2>/dev/null || true; fi
  SCRIPT_DIR="$(cd "$wd" && pwd -P)"
  export INSTALLER_WORKDIR="$SCRIPT_DIR"
}

# Determine SCRIPT_DIR robustly (works for /dev/fd when piped)
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

ENV_FILE="${SCRIPT_DIR}/.env"
CADDY_FILE="${SCRIPT_DIR}/Caddyfile"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
OPS_DIR="${SCRIPT_DIR}/ops"
BACKUP_SCRIPT="${OPS_DIR}/backup.sh"
mkdir -p "$OPS_DIR"

# ============== Basics ==============
require_rootless_sudo(){
  if [[ $EUID -eq 0 ]]; then
    warn "Running as root. It's safer to run as a normal user with sudo."
  fi
}

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
  if ! docker compose version >/dev/null 2>&1; then
    err "Docker Compose plugin not detected."; exit 1
  fi
  ok "Prerequisites ready"
}

# ============== Backup of existing config ==============
backup_existing(){
  if [[ -f "$ENV_FILE" || -f "$COMPOSE_FILE" || -f "$CADDY_FILE" ]]; then
    hdr "Backup existing config"
    local root="$SCRIPT_DIR"
    mkdir -p "$root" 2>/dev/null || root="${HOME:-/tmp}/digitalbot"
    mkdir -p "$root"
    local BACKUP_DIR="${root}/backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    [[ -f "$ENV_FILE" ]] && cp "$ENV_FILE" "$BACKUP_DIR/.env"
    [[ -f "$COMPOSE_FILE" ]] && cp "$COMPOSE_FILE" "$BACKUP_DIR/docker-compose.yml"
    [[ -f "$CADDY_FILE" ]] && cp "$CADDY_FILE" "$BACKUP_DIR/Caddyfile"
    ok "Backed up to $BACKUP_DIR"
  fi
}

# ============== Minimal generators (placeholders – adapt to your images) ==============
generate_env(){
  hdr "Generate .env"
  read -p "Project name [digitalbot]: " PROJECT_NAME; PROJECT_NAME=${PROJECT_NAME:-digitalbot}
  read -p "Main domain (e.g. example.com): " DOMAIN; [[ -z "$DOMAIN" ]] && { err "Domain required"; exit 1; }
  read -p "Client subdomain [client]: " CLIENT_SUB; CLIENT_SUB=${CLIENT_SUB:-client}
  CLIENT_APP_DOMAIN="${CLIENT_SUB}.${DOMAIN}"

  # credentials
  read -p "Postgres user [postgres]: " POSTGRES_USER; POSTGRES_USER=${POSTGRES_USER:-postgres}
  read -s -p "Postgres password: " POSTGRES_PASSWORD; echo; [[ -z "$POSTGRES_PASSWORD" ]] && { err "Postgres password required"; exit 1; }
  read -p "Postgres DB [digitalbot_db]: " POSTGRES_DB; POSTGRES_DB=${POSTGRES_DB:-digitalbot_db}

  read -p "RabbitMQ user [rabbit]: " RABBITMQ_USER; RABBITMQ_USER=${RABBITMQ_USER:-rabbit}
  read -s -p "RabbitMQ password: " RABBITMQ_PASSWORD; echo; [[ -z "$RABBITMQ_PASSWORD" ]] && { err "RabbitMQ password required"; exit 1; }

  read -s -p "Redis password: " REDIS_PASSWORD; echo; [[ -z "$REDIS_PASSWORD" ]] && { err "Redis password required"; exit 1; }

  read -p "Enable Caddy reverse proxy? (y/N): " EN_CADDY; EN_CADDY=${EN_CADDY:-N}

  cat >"$ENV_FILE"<<EOF
COMPOSE_PROJECT_NAME=${PROJECT_NAME}

# Domains
DOMAIN=${DOMAIN}
CLIENT_APP_DOMAIN=${CLIENT_APP_DOMAIN}

# Images (edit if you have a private registry/tags)
WEBAPP_IMAGE=docker.${DOMAIN}/digital-web:latest
CLIENT_APP_IMAGE=docker.${DOMAIN}/digital-client:latest
PROCESSOR_IMAGE=docker.${DOMAIN}/digital-processer:latest
ORDER_WORKER_IMAGE=docker.${DOMAIN}/digital-order-worker:latest
JOBS_IMAGE=docker.${DOMAIN}/digital-jobs:latest

# DB
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=${POSTGRES_DB}

# MQ/Cache
RABBITMQ_USER=${RABBITMQ_USER}
RABBITMQ_PASSWORD=${RABBITMQ_PASSWORD}
REDIS_PASSWORD=${REDIS_PASSWORD}

# Caddy
ENABLE_CADDY=${EN_CADDY}

# Sane defaults
PROCESSER_REPLICAS=2
ORDER_WORKER_REPLICAS=2
EOF
  chmod 600 "$ENV_FILE"
  ok ".env written → $ENV_FILE"
}

generate_compose(){
  hdr "Generate docker-compose.yml"
  cat >"$COMPOSE_FILE"<<'EOF'
version: "3.9"
services:
  webapp:
    image: ${WEBAPP_IMAGE}
    restart: unless-stopped
    environment:
      - ConnectionStrings__DefaultConnection=Host=postgres;Database=${POSTGRES_DB};Username=${POSTGRES_USER};Password=${POSTGRES_PASSWORD}
      - RabbitMq__HOST=rabbitmq
      - RabbitMq__Username=${RABBITMQ_USER}
      - RabbitMq__Password=${RABBITMQ_PASSWORD}
      - Redis__Host=redis
      - Redis__Password=${REDIS_PASSWORD}
      - ASPNETCORE_ENVIRONMENT=Production
    depends_on:
      postgres:
        condition: service_started
      rabbitmq:
        condition: service_started
      redis:
        condition: service_started
    deploy:
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
      - ConnectionStrings__DefaultConnection=Host=postgres;Database=${POSTGRES_DB};Username=${POSTGRES_USER};Password=${POSTGRES_PASSWORD}
      - RabbitMq__HOST=rabbitmq
      - RabbitMq__Username=${RABBITMQ_USER}
      - RabbitMq__Password=${RABBITMQ_PASSWORD}
      - Redis__Host=redis
      - Redis__Password=${REDIS_PASSWORD}
      - ASPNETCORE_ENVIRONMENT=Production
    depends_on:
      postgres: { condition: service_started }
      rabbitmq: { condition: service_started }
      redis: { condition: service_started }
    deploy:
      replicas: ${PROCESSER_REPLICAS}
      resources:
        limits: { cpus: "0.8", memory: "768M" }
    networks: [ digitalbot_internal ]

  worker:
    image: ${ORDER_WORKER_IMAGE}
    restart: unless-stopped
    environment:
      - ConnectionStrings__DefaultConnection=Host=postgres;Database=${POSTGRES_DB};Username=${POSTGRES_USER};Password=${POSTGRES_PASSWORD}
      - RabbitMq__HOST=rabbitmq
      - RabbitMq__Username=${RABBITMQ_USER}
      - RabbitMq__Password=${RABBITMQ_PASSWORD}
      - Redis__Host=redis
      - Redis__Password=${REDIS_PASSWORD}
      - ASPNETCORE_ENVIRONMENT=Production
    depends_on:
      postgres: { condition: service_started }
      rabbitmq: { condition: service_started }
      redis: { condition: service_started }
    deploy:
      replicas: ${ORDER_WORKER_REPLICAS}
      resources:
        limits: { cpus: "0.8", memory: "768M" }
    networks: [ digitalbot_internal ]

  jobs:
    image: ${JOBS_IMAGE}
    restart: unless-stopped
    environment:
      - ConnectionStrings__DefaultConnection=Host=postgres;Database=${POSTGRES_DB};Username=${POSTGRES_USER};Password=${POSTGRES_PASSWORD}
      - RabbitMq__HOST=rabbitmq
      - RabbitMq__Username=${RABBITMQ_USER}
      - RabbitMq__Password=${RABBITMQ_PASSWORD}
      - Redis__Host=redis
      - Redis__Password=${REDIS_PASSWORD}
      - ASPNETCORE_ENVIRONMENT=Production
    depends_on:
      postgres: { condition: service_started }
      rabbitmq: { condition: service_started }
      redis: { condition: service_started }
    networks: [ digitalbot_internal ]

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
    profiles: ["caddy"]   # only enabled when we want it

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
  ok "docker-compose.yml written → $COMPOSE_FILE"
}

generate_caddy(){
  if [[ "$(grep -E '^ENABLE_CADDY=.*' "$ENV_FILE" | cut -d= -f2)" == "y" || "$(grep -E '^ENABLE_CADDY=.*' "$ENV_FILE" | cut -d= -f2)" == "Y" ]]; then
    hdr "Generate Caddyfile"
    cat >"$CADDY_FILE"<<EOF
{$DOMAIN} {
  reverse_proxy webapp:8080 {
    header_up X-Real-IP {http.request.header.CF-Connecting-IP}
  }
}
{$CLIENT_APP_DOMAIN} {
  reverse_proxy client-app:80
}
EOF
    ok "Caddyfile written → $CADDY_FILE"
  else
    warn "Caddy disabled by config (ENABLE_CADDY!=y)."
  fi
}

# ============== Deploy / Update / Scale ==============
compose_cmd(){
  # enable caddy profile only when ENABLE_CADDY=y
  local profiles=()
  if [[ -f "$ENV_FILE" ]]; then
    local en="$(grep -E '^ENABLE_CADDY=.*' "$ENV_FILE" | cut -d= -f2 || true)"
    if [[ "$en" =~ ^[yY]$ ]]; then profiles+=( "--profile" "caddy" ); fi
  fi
  docker compose "${profiles[@]}" -f "$COMPOSE_FILE" "$@"
}

do_install(){
  require_rootless_sudo
  ensure_packages
  backup_existing
  generate_env
  generate_compose
  generate_caddy
  hdr "Deploy"
  compose_cmd pull
  compose_cmd up -d
  ok "Stack is up. Directory: $SCRIPT_DIR"
}

do_update(){
  ensure_packages
  hdr "Update"
  compose_cmd pull
  compose_cmd up -d
  ok "Updated."
}

do_scale(){
  hdr "Scale"
  read -p "processor replicas [2]: " P; P=${P:-2}
  read -p "worker replicas [2]: " W; W=${W:-2}
  sed -i "s/^PROCESSER_REPLICAS=.*/PROCESSER_REPLICAS=${P}/" "$ENV_FILE" || true
  sed -i "s/^ORDER_WORKER_REPLICAS=.*/ORDER_WORKER_REPLICAS=${W}/" "$ENV_FILE" || true
  compose_cmd up -d --scale processor="$P" --scale worker="$W"
  ok "Scaled. processor=${P} worker=${W}"
}

# ============== Postgres backup → ZIP → (optional) Telegram ==============
write_backup_script(){
  cat >"$BACKUP_SCRIPT"<<'EOS'
#!/usr/bin/env bash
set -euo pipefail
ENV_FILE="$(dirname "$0")/../.env"
source "$ENV_FILE"

STAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="$(dirname "$0")/../backups"
mkdir -p "$OUTDIR"
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
  ok "Backup script → $BACKUP_SCRIPT"
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
    ok "Cron installed: every 6h."
  fi
}

# ============== Registry login ==============
do_registry(){
  hdr "Docker Registry Login"
  read -p "Registry URL (e.g. docker.example.com) [docker.io]: " R; R=${R:-docker.io}
  read -p "Username: " U
  read -s -p "Password: " P; echo
  echo "$P" | docker login "$R" -u "$U" --password-stdin
  ok "Logged in to $R"
}

# ============== Menu / CLI ==============
show_menu(){
  hdr "Digital Bot Installer"
  cat <<MENU
Workdir: ${SCRIPT_DIR}

1) Install / Deploy
2) Update (pull + up)
3) Scale (processor/worker)
4) Backup setup (Postgres → ZIP → Telegram)
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
    *) err "Invalid choice"; exit 1 ;;
  esac
}

# Parse command verb (after possible --workdir)
case "${1:-}" in
  --install|install) shift || true; do_install ;;
  --update|update) shift || true; do_update ;;
  --scale|scale) shift || true; do_scale ;;
  --backup|backup) shift || true; configure_backup ;;
  --registry|registry) shift || true; do_registry ;;
  -h|--help) echo "Usage: $0 [--workdir /path] [--install|--update|--scale|--backup|--registry]"; exit 0 ;;
  *) show_menu ;;
esac
