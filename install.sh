#!/usr/bin/env bash
# Digital Bot Infra — Production‑grade Installer / Updater / Scaler / Backup
# Version: 2.0.0 (EN‑only)
# Goals:
#  - Safe defaults, health checks, graceful shutdowns
#  - Clean scaling (no container_name for scalable services)
#  - Dynamic Caddy (auto on/off)
#  - Multi-node ready (compute vs data nodes)
#  - Optional Postgres backup -> ZIP -> Telegram
#  - Non-interactive flags for CI/CD (GitHub Actions)
#  - Resource limits per service (CPUs / memory / ulimits)

set -euo pipefail

# ===== Colors & helpers =====
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'; BOLD='\033[1m'
log_i(){ echo -e "${BLUE}[INFO]${NC} $*"; }
log_s(){ echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_w(){ echo -e "${YELLOW}[WARN]${NC} $*"; }
log_e(){ echo -e "${RED}[ERROR]${NC} $*"; }
hdr(){ echo -e "\n${BOLD}${BLUE}═══════════════════════════════════════════════════════${NC}\n${BOLD}${BLUE}  $*${NC}\n${BOLD}${BLUE}═══════════════════════════════════════════════════════${NC}\n"; }

# ===== Paths =====
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
CADDY_FILE="${SCRIPT_DIR}/Caddyfile"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
BACKUP_SCRIPT="${SCRIPT_DIR}/ops/backup.sh"

# ===== UTF‑8 & fonts (avoid Persian rendering issues on server logs) =====
ensure_utf8(){
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -y >/dev/null 2>&1 || true
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y locales tzdata >/dev/null 2>&1 || true
    sudo locale-gen en_US.UTF-8 >/dev/null 2>&1 || true
    sudo apt-get install -y fonts-dejavu-core fonts-noto-core >/dev/null 2>&1 || true
  fi
  export LANG=en_US.UTF-8 LANGUAGE=en_US LC_ALL=en_US.UTF-8
}

# ===== System / Docker checks =====
check_root(){ if [[ $EUID -eq 0 ]]; then log_w "Run as non-root with sudo. Continue anyway? (y/N)"; read -r a; [[ ${a:-N} =~ ^[Yy]$ ]] || exit 1; fi; }
check_docker(){
  hdr "System / Docker"
  command -v docker >/dev/null 2>&1 || {
    log_w "Docker not found. Install now? (Y/n)"; read -r a
    if [[ ! ${a:-Y} =~ ^[Nn]$ ]]; then
      sudo apt-get update && sudo apt-get install -y ca-certificates curl gnupg lsb-release
      sudo mkdir -p /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
      sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      sudo usermod -aG docker "$USER"; log_s "Docker installed. Re-login may be required."
    else log_e "Docker is required."; exit 1; fi
  }
  docker compose version >/dev/null || { log_e "Docker Compose plugin missing."; exit 1; }
}

# ===== Backup existing config =====
backup_existing(){ local B="${SCRIPT_DIR}/backup_$(date +%Y%m%d_%H%M%S)"; mkdir -p "$B";
  [[ -f "$ENV_FILE" ]] && cp "$ENV_FILE" "$B/.env" || true
  [[ -f "$COMPOSE_FILE" ]] && cp "$COMPOSE_FILE" "$B/docker-compose.yml" || true
  [[ -f "$CADDY_FILE" ]] && cp "$CADDY_FILE" "$B/Caddyfile" || true
  log_s "Backup saved at $B"; }

# ===== Topology / Role =====
PRESET=two; ROLE=edgeapp
select_topology(){
  hdr "Topology / Role"
  echo -e "Topologies:\n  1) Single-node (all)\n  2) Two-node (Edge+App | Data)\n  3) Three-node (Edge | App | Data/Admin)"; read -p "Choose [2]: " p; p=${p:-2}
  case $p in 1) PRESET=single;; 2) PRESET=two;; 3) PRESET=three;; *) PRESET=two;; esac
  echo -e "\nRole for THIS server:"; case $PRESET in
    single) echo "  1) all-in-one"; read -p "Choice [1]: " r; ROLE="all";;
    two) echo -e "  1) edge+app\n  2) data"; read -p "Choice [1]: " r; ROLE=$([[ ${r:-1} == 2 ]] && echo data || echo edgeapp);;
    three) echo -e "  1) edge\n  2) app\n  3) data/admin"; read -p "Choice [2]: " r; case ${r:-2} in 1) ROLE=edge;; 2) ROLE=app;; 3) ROLE=data;; *) ROLE=app;; esac;;
  esac
  log_s "Preset=$PRESET Role=$ROLE"
}

# ===== Service toggles per role =====
INSTALL_POSTGRES=N; INSTALL_PGADMIN=N; INSTALL_RABBITMQ=N; INSTALL_REDIS=N; INSTALL_REDIS_INSIGHT=N; INSTALL_MINIO=N; INSTALL_PORTAINER=N
INSTALL_WEBAPP=N; INSTALL_CLIENT=N; INSTALL_PROCESSOR=N; INSTALL_WORKER=N; INSTALL_JOBS=N; INSTALL_CADDY=N
apply_role_defaults(){ case $ROLE in
  all)    INSTALL_POSTGRES=Y; INSTALL_RABBITMQ=Y; INSTALL_REDIS=Y; INSTALL_MINIO=Y; INSTALL_WEBAPP=Y; INSTALL_CLIENT=Y; INSTALL_PROCESSOR=Y; INSTALL_WORKER=Y; INSTALL_JOBS=Y; INSTALL_CADDY=Y; INSTALL_PGADMIN=Y; INSTALL_REDIS_INSIGHT=Y; INSTALL_PORTAINER=Y;;
  edgeapp)INSTALL_WEBAPP=Y; INSTALL_CLIENT=Y; INSTALL_PROCESSOR=Y; INSTALL_WORKER=Y; INSTALL_JOBS=Y; INSTALL_CADDY=Y;;
  data)   INSTALL_POSTGRES=Y; INSTALL_RABBITMQ=Y; INSTALL_REDIS=Y; INSTALL_MINIO=Y; INSTALL_PGADMIN=Y; INSTALL_REDIS_INSIGHT=Y; INSTALL_PORTAINER=Y;;
  edge)   INSTALL_CADDY=Y;;
  app)    INSTALL_WEBAPP=Y; INSTALL_CLIENT=Y; INSTALL_PROCESSOR=Y; INSTALL_WORKER=Y; INSTALL_JOBS=Y;;
esac; }

override_menu(){ hdr "Service Selection"; echo "Type y/n; Enter keeps default."; for v in POSTGRES PGADMIN RABBITMQ REDIS REDIS_INSIGHT MINIO PORTAINER WEBAPP CLIENT PROCESSOR WORKER JOBS CADDY; do cur=$(eval echo \${INSTALL_${v}}); read -p "$(printf '%-15s' "$v") [${cur}]: " ans; [[ -n "${ans:-}" ]] && eval INSTALL_${v}="$(echo "$ans" | tr a-z A-Z)"; done; }

# ===== Dynamic Caddy decision =====
auto_decide_caddy(){
  # external ingress disables caddy
  if [[ "${EXT_INGRESS:-false}" == "true" ]]; then INSTALL_CADDY=N; return; fi
  local has_public=0
  [[ "$INSTALL_WEBAPP" == Y ]] && has_public=1
  [[ "$INSTALL_CLIENT" == Y ]] && has_public=1
  [[ "$INSTALL_PGADMIN" == Y ]] && has_public=1
  [[ "$INSTALL_PORTAINER" == Y ]] && has_public=1
  [[ "$INSTALL_RABBITMQ" == Y ]] && has_public=1
  [[ "$INSTALL_REDIS_INSIGHT" == Y ]] && has_public=1
  [[ "$INSTALL_MINIO" == Y ]] && has_public=1
  if [[ "${EXPOSE_PUBLIC:-auto}" == "true" ]]; then INSTALL_CADDY=$([[ $has_public -eq 1 ]] && echo Y || echo N); return; fi
  if [[ "${EXPOSE_PUBLIC:-auto}" == "auto" ]]; then case "$ROLE" in edge|edgeapp|all) INSTALL_CADDY=$([[ $has_public -eq 1 ]] && echo Y || echo N);; *) INSTALL_CADDY=N;; esac; return; fi
  INSTALL_CADDY=N
}

# ===== Sizing (by perf or users) =====
WEBAPP_REP=2; PROCESSOR_REP=2; WORKER_REP=2; JOBS_REP=1
calc_by_perf(){ echo "Provide peak perf numbers (Enter = defaults)."; read -p "Backend peak RPS (after cache) [300]: " RPS; RPS=${RPS:-300}; read -p "Queue ingress (msg/sec) [25]: " L; L=${L:-25}; read -p "Avg processing time per message (sec) [0.2]: " T; T=${T:-0.2}; read -p "Utilization (0.5..0.9) [0.7]: " U; U=${U:-0.7}; WEBAPP_REP=$(( (RPS + 149) / 150 )); [[ $WEBAPP_REP -lt 2 ]] && WEBAPP_REP=2; need=$(python3 - <<PY
import math
L=${L}; T=${T}; U=${U}
print(math.ceil((L*T)/U))
PY
); WORKER_REP=$(( (need + 2) / 3 )); [[ $WORKER_REP -lt 2 ]] && WORKER_REP=2; PROCESSOR_REP=$(( (WEBAPP_REP + 1)/2 )); [[ $PROCESSOR_REP -lt 1 ]] && PROCESSOR_REP=1; }
calc_by_users(){ echo "We will derive perf from business numbers."; read -p "Total registered users: " U_TOTAL; read -p "Percent active (0-100) [10]: " P; P=${P:-10}; read -p "Peak concurrent percent of active [8]: " C; C=${C:-8}; read -p "Requests per active user per minute at peak [2]: " RPM; RPM=${RPM:-2}; read -p "Queue msgs per active user per minute [0.15]: " QPM; QPM=${QPM:-0.15}; read -p "Avg processing time per msg (sec) [0.2]: " T; T=${T:-0.2}; read -p "Utilization (0.5..0.9) [0.7]: " U; U=${U:-0.7}; U_ACTIVE=$(( U_TOTAL * P / 100 )); U_CONC=$(( U_ACTIVE * C / 100 )); RPS=$(python3 - <<PY
import math
conc=${U_CONC}; rpm=${RPM}
print(max(1, math.ceil(conc * (rpm/60.0))))
PY
); L=$(python3 - <<PY
import math
act=${U_ACTIVE}; qpm=${QPM}
print(max(1, math.ceil(act * (qpm/60.0))))
PY
); log_i "Derived: RPS=$RPS, queue msg/s=$L"; WEBAPP_REP=$(( (RPS + 149) / 150 )); [[ $WEBAPP_REP -lt 2 ]] && WEBAPP_REP=2; need=$(python3 - <<PY
import math
L=${L}; T=${T}; U=${U}
print(math.ceil((L*T)/U))
PY
); WORKER_REP=$(( (need + 2) / 3 )); [[ $WORKER_REP -lt 2 ]] && WORKER_REP=2; PROCESSOR_REP=$(( (WEBAPP_REP + 1)/2 )); [[ $PROCESSOR_REP -lt 1 ]] && PROCESSOR_REP=1; }
sizing_menu(){ hdr "Sizing"; echo "1) Provide performance numbers (RPS/msg/sec)"; echo "2) Provide business numbers (users/active %)"; read -p "Choose [2]: " m; m=${m:-2}; if [[ $m == 1 ]]; then calc_by_perf; else calc_by_users; fi; log_s "Replicas → webapp=$WEBAPP_REP, worker=$WORKER_REP, processor=$PROCESSOR_REP, jobs=$JOBS_REP"; }

# ===== Collect env =====
collect_env(){ hdr "Environment / Images / Domains"; read -p "Project name [digitalbot]: " PROJECT_NAME; PROJECT_NAME=${PROJECT_NAME:-digitalbot}; read -p "Main domain (example.com): " DOMAIN; while [[ -z "${DOMAIN:-}" ]]; do read -p "Main domain (example.com): " DOMAIN; done; read -p "Client subdomain [client]: " CLIENT_SUB; CLIENT_SUB=${CLIENT_SUB:-client}; CLIENT_APP_DOMAIN="${CLIENT_SUB}.${DOMAIN}"; read -p "Portainer subdomain [portainer]: " PORT_SUB; PORT_SUB=${PORT_SUB:-portainer}; PORTAINER_DOMAIN="${PORT_SUB}.${DOMAIN}"; read -p "RabbitMQ subdomain [rabbitmq]: " RMQ_SUB; RMQ_SUB=${RMQ_SUB:-rabbitmq}; RABBITMQ_DOMAIN="${RMQ_SUB}.${DOMAIN}"; read -p "PgAdmin subdomain [pgadmin]: " PG_SUB; PG_SUB=${PG_SUB:-pgadmin}; PGADMIN_DOMAIN="${PG_SUB}.${DOMAIN}"; read -p "RedisInsight subdomain [redis]: " RI_SUB; RI_SUB=${RI_SUB:-redis}; REDISINSIGHT_DOMAIN="${RI_SUB}.${DOMAIN}"; read -p "MinIO Console subdomain [minio]: " MINIO_SUB; MINIO_SUB=${MINIO_SUB:-minio}; MINIO_DOMAIN="${MINIO_SUB}.${DOMAIN}"; read -p "MinIO Files subdomain [files]: " FILES_SUB; FILES_SUB=${FILES_SUB:-files}; FILES_DOMAIN="${FILES_SUB}.${DOMAIN}"; read -p "Email for Let's Encrypt: " CADDY_ACME_EMAIL; while [[ -z "${CADDY_ACME_EMAIL:-}" ]]; do read -p "Email for Let's Encrypt: " CADDY_ACME_EMAIL; done; echo; log_i "Docker images (Enter = defaults using your registry)"; read -p "WEBAPP image [docker.${DOMAIN}/digital-web:latest]: " WEBAPP_IMAGE; WEBAPP_IMAGE=${WEBAPP_IMAGE:-"docker.${DOMAIN}/digital-web:latest"}; read -p "PROCESSOR image [docker.${DOMAIN}/digital-processer:latest]: " PROCESSOR_IMAGE; PROCESSOR_IMAGE=${PROCESSOR_IMAGE:-"docker.${DOMAIN}/digital-processer:latest"}; read -p "CLIENT image [docker.${DOMAIN}/digital-client:latest]: " CLIENT_APP_IMAGE; CLIENT_APP_IMAGE=${CLIENT_APP_IMAGE:-"docker.${DOMAIN}/digital-client:latest"}; read -p "ORDER WORKER image [docker.${DOMAIN}/digital-order-worker:latest]: " ORDER_WORKER_IMAGE; ORDER_WORKER_IMAGE=${ORDER_WORKER_IMAGE:-"docker.${DOMAIN}/digital-order-worker:latest"}; read -p "JOBS image [docker.${DOMAIN}/digital-jobs:latest]: " JOBS_IMAGE; JOBS_IMAGE=${JOBS_IMAGE:-"docker.${DOMAIN}/digital-jobs:latest"};
  # Public exposure toggles
  read -p "Expose HTTP services via THIS node? (true/false/auto) [auto]: " EXPOSE_PUBLIC; EXPOSE_PUBLIC=${EXPOSE_PUBLIC:-auto}
  read -p "Behind external ingress/load balancer? (true/false) [false]: " EXT_INGRESS; EXT_INGRESS=${EXT_INGRESS:-false}
  # Service credentials
  if [[ $INSTALL_POSTGRES == Y ]]; then echo; log_i "Postgres"; read -p "User [appuser]: " POSTGRES_USER; POSTGRES_USER=${POSTGRES_USER:-appuser}; read -sp "Password: " POSTGRES_PASSWORD; echo; while [[ -z "${POSTGRES_PASSWORD:-}" ]]; do read -sp "Password: " POSTGRES_PASSWORD; echo; done; read -p "DB name [digitalbot_db]: " POSTGRES_DB; POSTGRES_DB=${POSTGRES_DB:-digitalbot_db}; fi
  if [[ $INSTALL_RABBITMQ == Y ]]; then echo; log_i "RabbitMQ"; read -p "User [appmq]: " RABBITMQ_USER; RABBITMQ_USER=${RABBITMQ_USER:-appmq}; read -sp "Password: " RABBITMQ_PASSWORD; echo; while [[ -z "${RABBITMQ_PASSWORD:-}" ]]; do read -sp "Password: " RABBITMQ_PASSWORD; echo; done; fi
  if [[ $INSTALL_REDIS == Y ]]; then echo; log_i "Redis"; read -sp "Password: " REDIS_PASSWORD; echo; while [[ -z "${REDIS_PASSWORD:-}" ]]; do read -sp "Password: " REDIS_PASSWORD; echo; done; read -p "Enable AOF persistence? (y/N): " RAOF; [[ ${RAOF:-N} =~ ^[Yy]$ ]] && REDIS_AOF=yes || REDIS_AOF=no; fi
  if [[ $INSTALL_PGADMIN == Y ]]; then echo; log_i "PgAdmin"; read -p "Email: " PGADMIN_EMAIL; while [[ -z "${PGADMIN_EMAIL:-}" ]]; do read -p "Email: " PGADMIN_EMAIL; done; read -sp "Password: " PGADMIN_PASSWORD; echo; while [[ -z "${PGADMIN_PASSWORD:-}" ]]; do read -sp "Password: " PGADMIN_PASSWORD; echo; done; fi
  if [[ $INSTALL_MINIO == Y ]]; then echo; log_i "MinIO"; read -p "Access Key [minioadmin]: " MINIO_ACCESS_KEY; MINIO_ACCESS_KEY=${MINIO_ACCESS_KEY:-minioadmin}; read -sp "Secret Key: " MINIO_SECRET_KEY; echo; while [[ -z "${MINIO_SECRET_KEY:-}" ]]; do read -sp "Secret Key: " MINIO_SECRET_KEY; echo; done; read -p "Bucket [digitalbot]: " MINIO_BUCKET; MINIO_BUCKET=${MINIO_BUCKET:-digitalbot}; MINIO_ENDPOINT="minio:9000"; MINIO_SERVER_URL="https://${FILES_DOMAIN}"; MINIO_BROWSER_REDIRECT_URL="https://${MINIO_DOMAIN}"; MINIO_PUBLIC_URL="https://${FILES_DOMAIN}"; MINIO_REGION="us-east-1"; MINIO_USE_SSL="false"; STORAGE_PROVIDER="minio"; fi
  # Remote hosts for compute-only nodes (defaults for single node)
  POSTGRES_HOST=${POSTGRES_HOST:-postgres}; RABBITMQ_HOST=${RABBITMQ_HOST:-rabbitmq}; REDIS_HOST=${REDIS_HOST:-redis}
  VITE_BASE_API="https://${DOMAIN}"
}

# ===== .env generator =====
gen_env(){ hdr "Generate .env"; cat > "$ENV_FILE" << EOF
COMPOSE_PROJECT_NAME=${PROJECT_NAME}

# Images
WEBAPP_IMAGE=${WEBAPP_IMAGE}
PROCESSOR_IMAGE=${PROCESSOR_IMAGE}
CLIENT_APP_IMAGE=${CLIENT_APP_IMAGE}
ORDER_WORKER_IMAGE=${ORDER_WORKER_IMAGE}
JOBS_IMAGE=${JOBS_IMAGE}

# Replicas (computed)
WEBAPP_REPLICAS=${WEBAPP_REP}
PROCESSER_REPLICAS=${PROCESSOR_REP}
ORDER_WORKER_REPLICAS=${WORKER_REP}
JOBS_REPLICAS=${JOBS_REP}

# Domains
DOMAIN=${DOMAIN}
CLIENT_APP_DOMAIN=${CLIENT_APP_DOMAIN}
PORTAINER_DOMAIN=${PORTAINER_DOMAIN}
RABBITMQ_DOMAIN=${RABBITMQ_DOMAIN}
PGADMIN_DOMAIN=${PGADMIN_DOMAIN}
REDISINSIGHT_DOMAIN=${REDISINSIGHT_DOMAIN}
MINIO_DOMAIN=${MINIO_DOMAIN}
FILES_DOMAIN=${FILES_DOMAIN}

# ACME / Exposure
CADDY_ACME_EMAIL=${CADDY_ACME_EMAIL}
EXPOSE_PUBLIC=${EXPOSE_PUBLIC}
EXT_INGRESS=${EXT_INGRESS}

# Data service hosts (for multi-node)
POSTGRES_HOST=${POSTGRES_HOST}
RABBITMQ_HOST=${RABBITMQ_HOST}
REDIS_HOST=${REDIS_HOST}

# DB / MQ / Redis credentials
POSTGRES_USER=${POSTGRES_USER:-appuser}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-changeme}
POSTGRES_DB=${POSTGRES_DB:-digitalbot_db}

RABBITMQ_USER=${RABBITMQ_USER:-appmq}
RABBITMQ_PASSWORD=${RABBITMQ_PASSWORD:-changeme}

REDIS_PASSWORD=${REDIS_PASSWORD:-changeme}
REDIS_AOF=${REDIS_AOF:-no}

# PgAdmin
PGADMIN_EMAIL=${PGADMIN_EMAIL:-admin@example.com}
PGADMIN_PASSWORD=${PGADMIN_PASSWORD:-changeme}

# Client
VITE_BASE_API=${VITE_BASE_API}

# MinIO
STORAGE_PROVIDER=${STORAGE_PROVIDER:-minio}
MINIO_ACCESS_KEY=${MINIO_ACCESS_KEY:-minioadmin}
MINIO_SECRET_KEY=${MINIO_SECRET_KEY:-changeme}
MINIO_BUCKET=${MINIO_BUCKET:-digitalbot}
MINIO_ENDPOINT=${MINIO_ENDPOINT:-minio:9000}
MINIO_SERVER_URL=${MINIO_SERVER_URL:-http://localhost:9002}
MINIO_BROWSER_REDIRECT_URL=${MINIO_BROWSER_REDIRECT_URL:-http://localhost:9003}
MINIO_PUBLIC_URL=${MINIO_PUBLIC_URL:-http://localhost:9002}
MINIO_REGION=${MINIO_REGION:-us-east-1}
MINIO_USE_SSL=${MINIO_USE_SSL:-false}

# Backup (defaults off; enable via menu)
BACKUP_ENABLED=${BACKUP_ENABLED:-false}
BACKUP_SCOPE=${BACKUP_SCOPE:-single}
BACKUP_INTERVAL_HOURS=${BACKUP_INTERVAL_HOURS:-6}
BACKUP_KEEP_DAYS=${BACKUP_KEEP_DAYS:-7}
BACKUP_DB_NAME=${BACKUP_DB_NAME:-${POSTGRES_DB:-digitalbot_db}}
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN:-}
TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID:-}

# Resource limits (tweak as needed)
WEBAPP_CPUS=${WEBAPP_CPUS:-1.5}
WEBAPP_MEM=${WEBAPP_MEM:-1g}
PROCESSOR_CPUS=${PROCESSOR_CPUS:-1}
PROCESSOR_MEM=${PROCESSOR_MEM:-768m}
WORKER_CPUS=${WORKER_CPUS:-0.75}
WORKER_MEM=${WORKER_MEM:-512m}
JOBS_CPUS=${JOBS_CPUS:-0.5}
JOBS_MEM=${JOBS_MEM:-384m}
DB_MEM=${DB_MEM:-2g}
RABBIT_MEM=${RABBIT_MEM:-1g}
REDIS_MEM=${REDIS_MEM:-512m}
MINIO_MEM=${MINIO_MEM:-1g}

# Role summary
INSTALL_POSTGRES=${INSTALL_POSTGRES}
INSTALL_PGADMIN=${INSTALL_PGADMIN}
INSTALL_RABBITMQ=${INSTALL_RABBITMQ}
INSTALL_REDIS=${INSTALL_REDIS}
INSTALL_REDIS_INSIGHT=${INSTALL_REDIS_INSIGHT}
INSTALL_MINIO=${INSTALL_MINIO}
INSTALL_PORTAINER=${INSTALL_PORTAINER}
INSTALL_WEBAPP=${INSTALL_WEBAPP}
INSTALL_CLIENT=${INSTALL_CLIENT}
INSTALL_PROCESSOR=${INSTALL_PROCESSOR}
INSTALL_WORKER=${INSTALL_WORKER}
INSTALL_JOBS=${INSTALL_JOBS}
INSTALL_CADDY=${INSTALL_CADDY}
EOF
  chmod 600 "$ENV_FILE"; log_s ".env created";
}

# ===== Caddyfile (auto-generated only if needed) =====
gen_caddyfile(){ [[ "$INSTALL_CADDY" != Y ]] && { log_w "Caddy disabled"; return 0; } ; hdr "Generate Caddyfile"; cat > "$CADDY_FILE" << EOF
{
  email {\$CADDY_ACME_EMAIL}
}

(handle_response) {
  header {
    Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    X-Content-Type-Options "nosniff"
    X-Frame-Options "DENY"
    Referrer-Policy "no-referrer"
  }
}

${INSTALL_WEBAPP:+${DOMAIN} {
  reverse_proxy webapp:8080
  import handle_response
}}

${INSTALL_CLIENT:+${CLIENT_APP_DOMAIN} {
  reverse_proxy client-app:80
  import handle_response
}}

${INSTALL_PGADMIN:+${PGADMIN_DOMAIN} {
  reverse_proxy pgadmin:80
  import handle_response
}}

${INSTALL_PORTAINER:+${PORTAINER_DOMAIN} {
  reverse_proxy portainer:9000
  import handle_response
}}

${INSTALL_RABBITMQ:+${RABBITMQ_DOMAIN} {
  reverse_proxy rabbitmq:15672
  import handle_response
}}

${INSTALL_REDIS_INSIGHT:+${REDISINSIGHT_DOMAIN} {
  reverse_proxy redisinsight:5540
  import handle_response
}}

${INSTALL_MINIO:+${MINIO_DOMAIN} {
  reverse_proxy minio:9001
  import handle_response
}}

${INSTALL_MINIO:+${FILES_DOMAIN} {
  reverse_proxy minio:9000
  import handle_response
}}
EOF
  log_s "Caddyfile generated"; }

# ===== Compose generator (resource limits, healthchecks, graceful) =====
gen_compose(){ hdr "Generate docker-compose.yml"; source "$ENV_FILE"; [[ "${REDIS_AOF}" == "yes" ]] && REDIS_CMD='["redis-server","--requirepass","${REDIS_PASSWORD}","--appendonly","yes","--appendfsync","everysec"]' || REDIS_CMD='["redis-server","--requirepass","${REDIS_PASSWORD}"]'; cat > "$COMPOSE_FILE" << 'YAML'
version: "3.9"

services:
YAML
  # Caddy (only if enabled)
  if [[ "$INSTALL_CADDY" == "Y" ]]; then cat >> "$COMPOSE_FILE" << 'YAML'
  caddy:
    image: caddy:2
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    environment:
      - CADDY_ACME_EMAIL=${CADDY_ACME_EMAIL}
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy-data:/data
      - caddy-config:/config
    networks: [digitalbot_web]
    stop_grace_period: 20s
    ulimits:
      nofile: { soft: 65536, hard: 65536 }
    mem_limit: 512m
    cpus: 0.5
YAML
    echo "    depends_on:" >> "$COMPOSE_FILE"
    [[ "$INSTALL_WEBAPP" == "Y" ]] && echo "      - webapp" >> "$COMPOSE_FILE"
    [[ "$INSTALL_CLIENT" == "Y" ]] && echo "      - client-app" >> "$COMPOSE_FILE"
    [[ "$INSTALL_PGADMIN" == "Y" ]] && echo "      - pgadmin" >> "$COMPOSE_FILE"
    [[ "$INSTALL_RABBITMQ" == "Y" ]] && echo "      - rabbitmq" >> "$COMPOSE_FILE"
    [[ "$INSTALL_REDIS_INSIGHT" == "Y" ]] && echo "      - redisinsight" >> "$COMPOSE_FILE"
    [[ "$INSTALL_PORTAINER" == "Y" ]] && echo "      - portainer" >> "$COMPOSE_FILE"
    [[ "$INSTALL_MINIO" == "Y" ]] && { echo "      - minio" >> "$COMPOSE_FILE"; echo "      - minio-init" >> "$COMPOSE_FILE"; }
    echo "" >> "$COMPOSE_FILE"
  fi

  # Portainer
  if [[ "$INSTALL_PORTAINER" == "Y" ]]; then cat >> "$COMPOSE_FILE" << 'YAML'
  portainer:
    image: portainer/portainer-ce:latest
    restart: unless-stopped
    command: -H unix:///var/run/docker.sock
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer-data:/data
    networks: [digitalbot_web]
    mem_limit: 256m
    cpus: 0.3
YAML
  fi

  # Client
  if [[ "$INSTALL_CLIENT" == "Y" ]]; then cat >> "$COMPOSE_FILE" << 'YAML'
  client-app:
    image: ${CLIENT_APP_IMAGE}
    restart: unless-stopped
    networks: [digitalbot_web]
    mem_limit: 256m
    cpus: 0.5
YAML
  fi

  # Webapp (scalable)
  if [[ "$INSTALL_WEBAPP" == "Y" ]]; then cat >> "$COMPOSE_FILE" << 'YAML'
  webapp:
    image: ${WEBAPP_IMAGE}
    restart: unless-stopped
    environment:
      - ConnectionStrings__DefaultConnection=Host=${POSTGRES_HOST};Database=${POSTGRES_DB};Username=${POSTGRES_USER};Password=${POSTGRES_PASSWORD}
      - CLIENT_APP_DOMAIN=${CLIENT_APP_DOMAIN}
      - ASPNETCORE_ENVIRONMENT=Production
      - RabbitMq__HOST=${RABBITMQ_HOST}
      - RabbitMq__Username=${RABBITMQ_USER}
      - RabbitMq__Password=${RABBITMQ_PASSWORD}
      - Redis__Host=${REDIS_HOST}
      - Redis__Password=${REDIS_PASSWORD}
      - DOMAIN=${DOMAIN}
      - Storage__Provider=${STORAGE_PROVIDER}
      - Storage__PublicBaseUrl=${MINIO_PUBLIC_URL}
      - Storage__Minio__Endpoint=${MINIO_ENDPOINT}
      - Storage__Minio__AccessKey=${MINIO_ACCESS_KEY}
      - Storage__Minio__SecretKey=${MINIO_SECRET_KEY}
      - Storage__Minio__Bucket=${MINIO_BUCKET}
      - Storage__Minio__Region=${MINIO_REGION}
      - Storage__Minio__UseSSL=${MINIO_USE_SSL}
    networks: [digitalbot_web, digitalbot_internal]
    healthcheck:
      test: ["CMD","wget","-qO-","http://localhost:8080/healthz"]
      interval: 15s
      timeout: 5s
      retries: 5
    stop_grace_period: 45s
    mem_limit: ${WEBAPP_MEM}
    cpus: ${WEBAPP_CPUS}
    ulimits:
      nofile: { soft: 65536, hard: 65536 }
YAML
  fi

  # RabbitMQ
  if [[ "$INSTALL_RABBITMQ" == "Y" ]]; then cat >> "$COMPOSE_FILE" << 'YAML'
  rabbitmq:
    image: rabbitmq:3-management
    restart: unless-stopped
    environment:
      - RABBITMQ_DEFAULT_USER=${RABBITMQ_USER}
      - RABBITMQ_DEFAULT_PASS=${RABBITMQ_PASSWORD}
    volumes: [ "rabbitmq-data:/var/lib/rabbitmq" ]
    networks: [digitalbot_internal, digitalbot_web]
    healthcheck:
      test: ["CMD","rabbitmq-diagnostics","status"]
      interval: 15s
      timeout: 5s
      retries: 5
    stop_grace_period: 30s
    mem_limit: ${RABBIT_MEM}
    cpus: 0.8
YAML
  fi

  # Postgres
  if [[ "$INSTALL_POSTGRES" == "Y" ]]; then cat >> "$COMPOSE_FILE" << 'YAML'
  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB}
    volumes: [ "postgres-data:/var/lib/postgresql/data" ]
    networks: [digitalbot_web, digitalbot_internal]
    healthcheck:
      test: ["CMD-SHELL","pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 6
    stop_grace_period: 60s
    mem_limit: ${DB_MEM}
    cpus: 1.5
YAML
  fi

  # PgAdmin
  if [[ "$INSTALL_PGADMIN" == "Y" ]]; then cat >> "$COMPOSE_FILE" << 'YAML'
  pgadmin:
    image: dpage/pgadmin4
    restart: unless-stopped
    environment:
      - PGADMIN_DEFAULT_EMAIL=${PGADMIN_EMAIL}
      - PGADMIN_DEFAULT_PASSWORD=${PGADMIN_PASSWORD}
    networks: [digitalbot_web, digitalbot_internal]
    mem_limit: 384m
    cpus: 0.5
YAML
  fi

  # Processor (scalable)
  if [[ "$INSTALL_PROCESSOR" == "Y" ]]; then cat >> "$COMPOSE_FILE" << 'YAML'
  processor:
    image: ${PROCESSOR_IMAGE}
    restart: unless-stopped
    environment:
      - ConnectionStrings__DefaultConnection=Host=${POSTGRES_HOST};Database=${POSTGRES_DB};Username=${POSTGRES_USER};Password=${POSTGRES_PASSWORD}
      - ASPNETCORE_ENVIRONMENT=Production
      - CLIENT_APP_DOMAIN=${CLIENT_APP_DOMAIN}
      - RabbitMq__HOST=${RABBITMQ_HOST}
      - RabbitMq__Username=${RABBITMQ_USER}
      - RabbitMq__Password=${RABBITMQ_PASSWORD}
      - Redis__Host=${REDIS_HOST}
      - Redis__Password=${REDIS_PASSWORD}
      - DOMAIN=${DOMAIN}
      - Storage__Provider=${STORAGE_PROVIDER}
      - Storage__PublicBaseUrl=${MINIO_PUBLIC_URL}
      - Storage__Minio__Endpoint=${MINIO_ENDPOINT}
      - Storage__Minio__AccessKey=${MINIO_ACCESS_KEY}
      - Storage__Minio__SecretKey=${MINIO_SECRET_KEY}
      - Storage__Minio__Bucket=${MINIO_BUCKET}
      - Storage__Minio__Region=${MINIO_REGION}
      - Storage__Minio__UseSSL=${MINIO_USE_SSL}
    networks: [digitalbot_internal, digitalbot_web]
    stop_grace_period: 45s
    mem_limit: ${PROCESSOR_MEM}
    cpus: ${PROCESSOR_CPUS}
YAML
  fi

  # Worker (scalable, graceful)
  if [[ "$INSTALL_WORKER" == "Y" ]]; then cat >> "$COMPOSE_FILE" << 'YAML'
  worker:
    image: ${ORDER_WORKER_IMAGE}
    restart: unless-stopped
    environment:
      - ConnectionStrings__DefaultConnection=Host=${POSTGRES_HOST};Database=${POSTGRES_DB};Username=${POSTGRES_USER};Password=${POSTGRES_PASSWORD}
      - ASPNETCORE_ENVIRONMENT=Production
      - RabbitMq__HOST=${RABBITMQ_HOST}
      - RabbitMq__Username=${RABBITMQ_USER}
      - RabbitMq__Password=${RABBITMQ_PASSWORD}
      - CLIENT_APP_DOMAIN=${CLIENT_APP_DOMAIN}
      - DOMAIN=${DOMAIN}
      - Redis__Host=${REDIS_HOST}
      - Redis__Password=${REDIS_PASSWORD}
      - Storage__Provider=${STORAGE_PROVIDER}
      - Storage__PublicBaseUrl=${MINIO_PUBLIC_URL}
      - Storage__Minio__Endpoint=${MINIO_ENDPOINT}
      - Storage__Minio__AccessKey=${MINIO_ACCESS_KEY}
      - Storage__Minio__SecretKey=${MINIO_SECRET_KEY}
      - Storage__Minio__Bucket=${MINIO_BUCKET}
      - Storage__Minio__Region=${MINIO_REGION}
      - Storage__Minio__UseSSL=${MINIO_USE_SSL}
    networks: [digitalbot_internal, digitalbot_web]
    stop_signal: SIGTERM
    stop_grace_period: 60s
    mem_limit: ${WORKER_MEM}
    cpus: ${WORKER_CPUS}
YAML
  fi

  # Jobs
  if [[ "$INSTALL_JOBS" == "Y" ]]; then cat >> "$COMPOSE_FILE" << 'YAML'
  jobs:
    image: ${JOBS_IMAGE}
    restart: unless-stopped
    environment:
      - ConnectionStrings__DefaultConnection=Host=${POSTGRES_HOST};Database=${POSTGRES_DB};Username=${POSTGRES_USER};Password=${POSTGRES_PASSWORD}
      - ASPNETCORE_ENVIRONMENT=Production
      - CLIENT_APP_DOMAIN=${CLIENT_APP_DOMAIN}
      - RabbitMq__HOST=${RABBITMQ_HOST}
      - RabbitMq__Username=${RABBITMQ_USER}
      - RabbitMq__Password=${RABBITMQ_PASSWORD}
      - Redis__Host=${REDIS_HOST}
      - Redis__Password=${REDIS_PASSWORD}
      - DOMAIN=${DOMAIN}
      - Storage__Provider=${STORAGE_PROVIDER}
      - Storage__PublicBaseUrl=${MINIO_PUBLIC_URL}
      - Storage__Minio__Endpoint=${MINIO_ENDPOINT}
      - Storage__Minio__AccessKey=${MINIO_ACCESS_KEY}
      - Storage__Minio__SecretKey=${MINIO_SECRET_KEY}
      - Storage__Minio__Bucket=${MINIO_BUCKET}
      - Storage__Minio__Region=${MINIO_REGION}
      - Storage__Minio__UseSSL=${MINIO_USE_SSL}
    networks: [digitalbot_internal, digitalbot_web]
    stop_grace_period: 30s
    mem_limit: ${JOBS_MEM}
    cpus: ${JOBS_CPUS}
YAML
  fi

  # Redis
  if [[ "$INSTALL_REDIS" == "Y" ]]; then cat >> "$COMPOSE_FILE" << YAML
  redis:
    image: redis:7-alpine
    restart: unless-stopped
    command: ${REDIS_CMD}
    networks: [digitalbot_internal]
    healthcheck:
      test: ["CMD","redis-cli","-a","\${REDIS_PASSWORD}","ping"]
      interval: 10s
      timeout: 3s
      retries: 5
    stop_grace_period: 20s
    mem_limit: ${REDIS_MEM}
    cpus: 0.4
YAML
  fi

  # RedisInsight (port 5540)
  if [[ "$INSTALL_REDIS_INSIGHT" == "Y" ]]; then cat >> "$COMPOSE_FILE" << 'YAML'
  redisinsight:
    image: redis/redisinsight:latest
    restart: unless-stopped
    networks: [digitalbot_web, digitalbot_internal]
    mem_limit: 256m
    cpus: 0.3
YAML
  fi

  # MinIO + init with healthcheck + retry alias
  if [[ "$INSTALL_MINIO" == "Y" ]]; then cat >> "$COMPOSE_FILE" << 'YAML'
  minio:
    image: minio/minio:latest
    restart: unless-stopped
    environment:
      MINIO_ROOT_USER: ${MINIO_ACCESS_KEY}
      MINIO_ROOT_PASSWORD: ${MINIO_SECRET_KEY}
      MINIO_SERVER_URL: ${MINIO_SERVER_URL}
      MINIO_BROWSER_REDIRECT_URL: ${MINIO_BROWSER_REDIRECT_URL}
    command: server /data --console-address ":9001"
    volumes: [ "minio-data:/data" ]
    networks: [digitalbot_internal, digitalbot_web]
    healthcheck:
      test: ["CMD-SHELL","wget -qO- http://localhost:9000/minio/health/ready >/dev/null 2>&1"]
      interval: 10s
      timeout: 5s
      retries: 12
    stop_grace_period: 30s
    mem_limit: ${MINIO_MEM}
    cpus: 0.8

  minio-init:
    image: minio/mc:latest
    depends_on:
      minio:
        condition: service_healthy
    entrypoint: >
      /bin/sh -c "
      set -e;
      echo 'Setting MinIO alias...';
      for i in $(seq 1 60); do
        if /usr/bin/mc alias set local http://minio:9000 ${MINIO_ACCESS_KEY} ${MINIO_SECRET_KEY} >/dev/null 2>&1; then
          echo 'MinIO alias set.'; break; fi; echo 'MinIO not ready...'; sleep 2; done;
      /usr/bin/mc alias ls | grep -q '^local ' || { echo 'Failed to set alias'; exit 1; }
      /usr/bin/mc mb -p local/${MINIO_BUCKET} || true;
      /usr/bin/mc anonymous set download local/${MINIO_BUCKET} || true;
      echo 'MinIO bucket initialized.'
      "
    networks: [digitalbot_internal]
    mem_limit: 128m
    cpus: 0.2
YAML
  fi

  # Postgres backup (optional)
  if [[ "${BACKUP_ENABLED}" == "true" && "${INSTALL_POSTGRES}" == "Y" ]]; then mkdir -p "$(dirname "$BACKUP_SCRIPT")"; cat > "$BACKUP_SCRIPT" << 'BASH'
#!/bin/sh
set -euo pipefail
if ! command -v pg_dump >/dev/null 2>&1; then apk add --no-cache postgresql-client curl zip tzdata >/dev/null; fi
: "${POSTGRES_HOST:=postgres}"; : "${POSTGRES_PORT:=5432}"; : "${POSTGRES_USER:=postgres}"; : "${POSTGRES_PASSWORD:=}"
: "${BACKUP_SCOPE:=single}"; : "${BACKUP_DB_NAME:=postgres}"
: "${BACKUP_INTERVAL_HOURS:=6}"; : "${BACKUP_KEEP_DAYS:=7}"
: "${TELEGRAM_BOT_TOKEN:=}"; : "${TELEGRAM_CHAT_ID:=}"; : "${TZ:=Asia/Dubai}"
export PGPASSWORD="$POSTGRES_PASSWORD"
sleep_hours(){ sleep "$(( $1 * 3600 ))"; }
send_tg(){ f="$1"; cap="$2"; [ -z "$TELEGRAM_BOT_TOKEN" -o -z "$TELEGRAM_CHAT_ID" ] && { echo "[WARN] TG not set"; return 0; }
  curl -sS -X POST -F "chat_id=${TELEGRAM_CHAT_ID}" -F "document=@${f}" -F "caption=${cap}" "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" | grep -q '"ok":true' && echo "[OK] telegram" || echo "[ERR] telegram"; }
one(){ ts=$(date +"%Y%m%d_%H%M%S"); tdir="/tmp/pgbkp"; odir="/backups"; mkdir -p "$tdir" "$odir"
  if [ "$BACKUP_SCOPE" = "all" ]; then dump="$tdir/pg-all-${ts}.sql"; echo "[INFO] pg_dumpall"; pg_dumpall -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -c > "$dump"; zipf="$odir/pg-all-${ts}.zip"; (cd "$tdir" && zip -q -9 "$(basename "$zipf")" "$(basename "$dump")"); mv "$tdir/$(basename "$zipf")" "$zipf"; rm -f "$dump"; cap="Postgres ALL ${ts}"; else dump="$tdir/${BACKUP_DB_NAME}-${ts}.dump"; echo "[INFO] pg_dump $BACKUP_DB_NAME"; pg_dump -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$BACKUP_DB_NAME" -F c -Z 9 -f "$dump"; zipf="$odir/${BACKUP_DB_NAME}-${ts}.zip"; (cd "$tdir" && zip -q -9 "$(basename "$zipf")" "$(basename "$dump")"); mv "$tdir/$(basename "$zipf")" "$zipf"; rm -f "$dump"; cap="Postgres ${BACKUP_DB_NAME} ${ts}"; fi
  find "$odir" -type f -mtime +"${BACKUP_KEEP_DAYS}" -name "*.zip" -delete || true; send_tg "$zipf" "$cap" || true; }
trap "echo '[INFO] stop'; exit 0" TERM INT
[ "${1:-}" = "once" ] && { one; exit 0; }
echo "[INFO] loop ${BACKUP_INTERVAL_HOURS}h keep ${BACKUP_KEEP_DAYS}d"; while true; do one; sleep_hours "$BACKUP_INTERVAL_HOURS"; done
BASH
  chmod +x "$BACKUP_SCRIPT"
  cat >> "$COMPOSE_FILE" << 'YAML'
  pg-backup:
    image: alpine:3.20
    restart: unless-stopped
    environment:
      - TZ=Asia/Dubai
      - POSTGRES_HOST=${POSTGRES_HOST}
      - POSTGRES_PORT=5432
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - BACKUP_SCOPE=${BACKUP_SCOPE}
      - BACKUP_DB_NAME=${BACKUP_DB_NAME}
      - BACKUP_INTERVAL_HOURS=${BACKUP_INTERVAL_HOURS}
      - BACKUP_KEEP_DAYS=${BACKUP_KEEP_DAYS}
      - TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
      - TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID}
    volumes:
      - ./ops/backup.sh:/app/backup.sh:ro
      - pg-backups:/backups
    entrypoint: ["/bin/sh","/app/backup.sh"]
    networks: [digitalbot_internal]
    depends_on:
      postgres:
        condition: service_healthy
    mem_limit: 128m
    cpus: 0.2
YAML
  fi

  # Volumes & Networks
  cat >> "$COMPOSE_FILE" << 'YAML'

volumes:
  minio-data:
    name: minio_data
  postgres-data:
    name: postgres_data
  caddy-data:
    name: caddy_data
  caddy-config:
    name: caddy_config
  portainer-data:
    name: portainer_data
  rabbitmq-data:
    name: rabbitmq_data
  pg-backups:
    name: pg_backups

networks:
  digitalbot_web: {}
  digitalbot_internal:
    driver: bridge
    internal: true
YAML
  log_s "docker-compose.yml generated";
}

# ===== Deploy / Update / Scale (with warm-up) =====
wait_healthy(){ svc="$1"; timeout_s="${2:-180}"; log_i "Waiting for $svc to be healthy (<=${timeout_s}s)"; start=$(date +%s); while true; do st=$(docker inspect --format '{{json .State.Health.Status}}' $(docker compose ps -q "$svc" | head -n1) 2>/dev/null || true); [[ "$st" == '"healthy"' ]] && { log_s "$svc healthy"; break; }; now=$(date +%s); (( now - start > timeout_s )) && { log_w "$svc health timeout"; break; }; sleep 3; done; }

deploy_stack(){ hdr "Deploy"; docker compose pull; docker network create digitalbot_web 2>/dev/null || true; docker network create digitalbot_internal 2>/dev/null || true; docker compose up -d; [[ $INSTALL_WEBAPP == Y    ]] && docker compose up -d --scale webapp=${WEBAPP_REP}
  [[ $INSTALL_WORKER == Y    ]] && docker compose up -d --scale worker=${WORKER_REP}
  [[ $INSTALL_PROCESSOR == Y ]] && docker compose up -d --scale processor=${PROCESSOR_REP}
  [[ $INSTALL_JOBS == Y      ]] && docker compose up -d --scale jobs=${JOBS_REP}
  [[ $INSTALL_WEBAPP == Y    ]] && wait_healthy webapp 180 || true
  log_s "Services are up."; }

update_stack(){ hdr "Update (pull + up)"; docker compose pull; docker compose up -d; [[ $INSTALL_WEBAPP == Y ]] && wait_healthy webapp 180 || true; log_s "Updated."; }

scale_stack(){ hdr "Scale"; sizing_menu; sed -i "s/^WEBAPP_REPLICAS=.*/WEBAPP_REPLICAS=${WEBAPP_REP}/" "$ENV_FILE" || true; sed -i "s/^ORDER_WORKER_REPLICAS=.*/ORDER_WORKER_REPLICAS=${WORKER_REP}/" "$ENV_FILE" || true; sed -i "s/^PROCESSER_REPLICAS=.*/PROCESSER_REPLICAS=${PROCESSOR_REP}/" "$ENV_FILE" || true; sed -i "s/^JOBS_REPLICAS=.*/JOBS_REPLICAS=${JOBS_REP}/" "$ENV_FILE" || true; docker compose up -d --scale webapp=${WEBAPP_REP} --scale worker=${WORKER_REP} --scale processor=${PROCESSOR_REP} --scale jobs=${JOBS_REP}; [[ $INSTALL_WEBAPP == Y ]] && wait_healthy webapp 180 || true; log_s "Scaled."; }

# ===== Backup menu =====
backup_menu(){ hdr "Backup Setup/Edit"; source "$ENV_FILE"; read -p "Enable Postgres backup? (true/false) [${BACKUP_ENABLED:-false}]: " b; BACKUP_ENABLED=${b:-${BACKUP_ENABLED:-false}}; read -p "Scope (single/all) [${BACKUP_SCOPE:-single}]: " s; BACKUP_SCOPE=${s:-${BACKUP_SCOPE:-single}}; read -p "DB name (if single) [${BACKUP_DB_NAME:-${POSTGRES_DB:-digitalbot_db}}]: " dn; BACKUP_DB_NAME=${dn:-${BACKUP_DB_NAME:-${POSTGRES_DB:-digitalbot_db}}}; read -p "Interval hours [${BACKUP_INTERVAL_HOURS:-6}]: " ih; BACKUP_INTERVAL_HOURS=${ih:-${BACKUP_INTERVAL_HOURS:-6}}; read -p "Keep days [${BACKUP_KEEP_DAYS:-7}]: " kd; BACKUP_KEEP_DAYS=${kd:-${BACKUP_KEEP_DAYS:-7}}; read -p "Telegram bot token (optional): " tbt; TELEGRAM_BOT_TOKEN=${tbt:-${TELEGRAM_BOT_TOKEN:-}}; read -p "Telegram chat id (optional): " tci; TELEGRAM_CHAT_ID=${tci:-${TELEGRAM_CHAT_ID:-}}; for k in BACKUP_ENABLED BACKUP_SCOPE BACKUP_DB_NAME BACKUP_INTERVAL_HOURS BACKUP_KEEP_DAYS TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID; do v=$(eval echo \$$k); grep -q "^$k=" "$ENV_FILE" && sed -i "s|^$k=.*|$k=${v}|" "$ENV_FILE" || echo "$k=${v}" >> "$ENV_FILE"; done; gen_compose; docker compose up -d pg-backup || true; log_s "Backup config applied."; }

# ===== Add Compute Node (choose services) =====
add_compute_node(){ hdr "Add Compute Node"; INSTALL_POSTGRES=N; INSTALL_PGADMIN=N; INSTALL_RABBITMQ=N; INSTALL_REDIS=N; INSTALL_REDIS_INSIGHT=N; INSTALL_MINIO=N; INSTALL_PORTAINER=N; INSTALL_WEBAPP=N; INSTALL_CLIENT=N; INSTALL_PROCESSOR=N; INSTALL_WORKER=N; INSTALL_JOBS=N; INSTALL_CADDY=N; echo "Select services for THIS node (y/n):"; read -p "Web API (webapp)? [n]: " a; [[ ${a:-n} =~ ^[Yy]$ ]] && INSTALL_WEBAPP=Y; read -p "Client (client-app)? [n]: " a; [[ ${a:-n} =~ ^[Yy]$ ]] && INSTALL_CLIENT=Y; read -p "Processor? [n]: " a; [[ ${a:-n} =~ ^[Yy]$ ]] && INSTALL_PROCESSOR=Y; read -p "Worker? [n]: " a; [[ ${a:-n} =~ ^[Yy]$ ]] && INSTALL_WORKER=Y; read -p "Jobs? [n]: " a; [[ ${a:-n} =~ ^[Yy]$ ]] && INSTALL_JOBS=Y; # Caddy auto
  hdr "Remote Data Endpoints"; read -p "POSTGRES_HOST [10.0.0.5]: " POSTGRES_HOST; POSTGRES_HOST=${POSTGRES_HOST:-10.0.0.5}; read -p "RABBITMQ_HOST [10.0.0.5]: " RABBITMQ_HOST; RABBITMQ_HOST=${RABBITMQ_HOST:-10.0.0.5}; read -p "REDIS_HOST [10.0.0.5]: " REDIS_HOST; REDIS_HOST=${REDIS_HOST:-10.0.0.5}; collect_env; auto_decide_caddy; sed -i "s/^POSTGRES_HOST=.*/POSTGRES_HOST=${POSTGRES_HOST}/" "$ENV_FILE" || echo "POSTGRES_HOST=${POSTGRES_HOST}" >> "$ENV_FILE"; sed -i "s/^RABBITMQ_HOST=.*/RABBITMQ_HOST=${RABBITMQ_HOST}/" "$ENV_FILE" || echo "RABBITMQ_HOST=${RABBITMQ_HOST}" >> "$ENV_FILE"; sed -i "s/^REDIS_HOST=.*/REDIS_HOST=${REDIS_HOST}/" "$ENV_FILE" || echo "REDIS_HOST=${REDIS_HOST}" >> "$ENV_FILE"; sizing_menu; gen_env; gen_caddyfile; gen_compose; deploy_stack; }

# ===== Docker registry login (optional) =====
registry_login(){ hdr "Docker Registry Login"; echo "Login to a registry? (y/N)"; read -r a; [[ ${a:-N} =~ ^[Yy]$ ]] || return 0; read -p "Registry URL (e.g., docker.example.com): " rr; read -p "Username: " uu; read -sp "Password: " pp; echo; echo "$pp" | docker login "$rr" -u "$uu" --password-stdin && log_s "Logged in to $rr" || log_e "Login failed"; }

# ===== Non-interactive flags for CI/CD =====
main_install(){ ensure_utf8; check_root; check_docker; backup_existing; select_topology; apply_role_defaults; [[ "${SKIP_SERVICE_PROMPT:-false}" != "true" ]] && override_menu; sizing_menu; collect_env; auto_decide_caddy; gen_env; gen_caddyfile; gen_compose; echo -e "\n${YELLOW}${BOLD}Deploy now? (Y/n)${NC}"; read -r go; [[ ${go:-Y} =~ ^[Nn]$ ]] && { log_w "Cancelled"; exit 0; }; deploy_stack; log_s "Done."; }
main_update(){ [[ -f "$ENV_FILE" ]] || { log_e ".env not found"; exit 1; }; source "$ENV_FILE"; update_stack; }
main_scale(){ [[ -f "$ENV_FILE" ]] || { log_e ".env not found"; exit 1; }; source "$ENV_FILE"; scale_stack; }
main_backup(){ [[ -f "$ENV_FILE" ]] || { log_e ".env not found"; exit 1; }; backup_menu; }
main_addnode(){ add_compute_node; }
main_registry(){ registry_login; }

case "${1:-}" in
  --install)   shift; main_install;  exit 0 ;;
  --update)    shift; main_update;   exit 0 ;;
  --scale)     shift; main_scale;    exit 0 ;;
  --backup)    shift; main_backup;   exit 0 ;;
  --addnode)   shift; main_addnode;  exit 0 ;;
  --registry)  shift; main_registry; exit 0 ;;
esac

# ===== Menu =====
show_menu(){ clear; echo -e "${BLUE}"; cat << "EOF"
╔══════════════════════════════════════════════════════╗
║     Digital Bot Production Installer (v2.0.0)        ║
╠══════════════════════════════════════════════════════╣
║ 1) Install (fresh)                                   ║
║ 2) Update (pull + up)                                ║
║ 3) Scale (by users/perf)                             ║
║ 4) Backup setup/edit                                 ║
║ 5) Add Compute Node (choose services)                ║
║ 6) Docker Registry Login                             ║
║ 0) Exit                                              ║
╚══════════════════════════════════════════════════════╝
EOF
  echo -e "${NC}"; read -p "Choose: " c; case ${c:-1} in 1) main_install;; 2) main_update;; 3) main_scale;; 4) main_backup;; 5) main_addnode;; 6) main_registry;; 0) exit 0;; *) show_menu;; esac; }

show_menu
