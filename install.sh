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
# fixed RPM per active user (keep simple for scale)
RPM_PER_USER_DEFAULT=6
ROLE=""   # one of: all, edge-app, data, edge, app

calc_replicas_from_active() {
  local ACTIVE="$1"
  local RPM_PER_USER="${2:-$RPM_PER_USER_DEFAULT}"
  local RPS=$(( ACTIVE * RPM_PER_USER / 60 ))
  local need_mc=$(( RPS * 8 ))                    # 8m per request (tunable)
  local WEB=$(( (need_mc + 800) / 800 )); [[ $WEB -lt 2 ]] && WEB=2
  local PROC=$(( (ACTIVE/2000) + 1 ))
  local WORK=$(( (ACTIVE/3000) + 1 ))
  echo "$WEB $PROC $WORK"
}

gentle_bounce_service() {
  # sequential restart to avoid full drop
  local svc="$1"
  info "Gentle bounce for service: $svc"
  local ids
  ids=$(docker compose -f "$COMPOSE_FILE" ps -q "$svc")
  if [[ -z "$ids" ]]; then warn "No containers for $svc"; return 0; fi
  # restart one by one with short delay
  for id in $ids; do
    info "Restarting $svc container $id"
    docker restart "$id" >/dev/null
    sleep 2
  done
  ok "Gentle bounce done for $svc"
}

BOLD='\033[1m'; RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
hdr(){ echo -e "\n${BOLD}${BLUE}═══════════════════════════════════════════════════════${NC}\n${BOLD}${BLUE}  $*${NC}\n${BOLD}${BLUE}═══════════════════════════════════════════════════════${NC}\n"; }
info(){ echo -e "${BLUE}[INFO]${NC} $*"; }
ok(){ echo -e "${GREEN}[SUCCESS]${NC} $*"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $*"; }
err(){ echo -e "${RED}[ERROR]${NC} $*"; }
# Strong password generator
gen_pw(){ LC_ALL=C tr -dc 'A-Za-z0-9!@#%^_+=' </dev/urandom | head -c ${1:-24}; echo; }
# Prompt until non-empty (required field)
ask_required() {
  local prompt="$1" val=""
  while :; do
    read -p "$prompt" val
    if [[ -n "$val" ]]; then
      printf "%s" "$val"
      return 0
    else
      err "This field is required"
    fi
  done
}

# ask integer within range, with default
ask_int_in_range() {
  local prompt="$1" def="$2" lo="$3" hi="$4" v
  while :; do
    read -p "$prompt" v
    v="${v:-$def}"
    # trim whitespace
    v="${v//[$'\t\r\n ']}"
    v="$(normalize_digits "$v")"
    [[ "$v" =~ ^[0-9]+$ ]] && (( v>=lo && v<=hi )) && { printf "%s" "$v"; return 0; }
    err "Enter an integer between $lo and $hi"
  done
}

# ask for yes/no with default; returns 'y' or 'n'
ask_yn() {
  local prompt="$1" def="${2:-N}" ans
  while :; do
    read -p "$prompt" ans
    ans="${ans:-$def}"
    # trim whitespace
    ans="${ans//[$'\t\r\n ']}"
    case "${ans,,}" in
      y|yes|true|1) printf "y"; return 0;;
      n|no|false|0) printf "n"; return 0;;
      *) err "Please answer y or n";;
    esac
  done
}

# Normalize Persian/Arabic-Indic digits to ASCII 0-9
normalize_digits() {
  local s="$1"
  # Arabic-Indic: ٠١٢٣٤٥٦٧٨٩
  s="${s//٠/0}"; s="${s//١/1}"; s="${s//٢/2}"; s="${s//٣/3}"; s="${s//٤/4}";
  s="${s//٥/5}"; s="${s//٦/6}"; s="${s//٧/7}"; s="${s//٨/8}"; s="${s//٩/9}"
  # Eastern Arabic-Indic (Persian): ۰۱۲۳۴۵۶۷۸۹
  s="${s//۰/0}"; s="${s//۱/1}"; s="${s//۲/2}"; s="${s//۳/3}"; s="${s//۴/4}";
  s="${s//۵/5}"; s="${s//۶/6}"; s="${s//۷/7}"; s="${s//۸/8}"; s="${s//۹/9}"
  # Remove thousands separators (comma) if present
  s="${s//,/}"
  printf "%s" "$s"
}

# Non-blocking DNS sanity check
dns_warn(){
  local host="$1" ip_self ip_dns
  ip_self="$(curl -fsS ifconfig.me 2>/dev/null || true)"
  # getent may not exist on minimal systems; try getent then fallback to nslookup
  if command -v getent >/dev/null 2>&1; then
    ip_dns="$(getent ahostsv4 "$host" | awk '{print $1; exit}' 2>/dev/null || true)"
  fi
  if [[ -z "$ip_dns" ]]; then
    ip_dns="$(nslookup "$host" 2>/dev/null | awk '/^Address: /{print $2; exit}' || true)"
  fi
  if [[ -z "$ip_dns" || -z "$ip_self" || "$ip_dns" != "$ip_self" ]]; then
    warn "DNS for ${host} does not seem to resolve to this server (${ip_self}). SSL issuance may fail."
  else
    info "DNS for ${host} points to this server (${ip_self})"
  fi
}

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
# replace the entire backup_existing() with this
KEEP_BACKUPS=${KEEP_BACKUPS:-3}

backup_existing(){
  local need_backup=0
  local last_dir=""
  local last_env="" last_comp="" last_caddy=""

  # Find the latest backup directory
  last_dir="$(ls -1dt "$SCRIPT_DIR"/backup_* 2>/dev/null | head -n1 || true)"
  if [[ -n "$last_dir" && -d "$last_dir" ]]; then
    [[ -f "$last_dir/.env" ]]               && last_env="$last_dir/.env"
    [[ -f "$last_dir/docker-compose.yml" ]] && last_comp="$last_dir/docker-compose.yml"
    [[ -f "$last_dir/Caddyfile" ]]          && last_caddy="$last_dir/Caddyfile"
  fi

  # If no current files exist, skip backup
  if [[ ! -f "$ENV_FILE" && ! -f "$COMPOSE_FILE" && ! -f "$CADDY_FILE" ]]; then
    return 0
  fi

  # Determine whether there are changes compared to the latest backup
  if [[ -f "$ENV_FILE" ]]; then
    if [[ ! -f "$last_env" ]] || ! cmp -s "$ENV_FILE" "$last_env"; then need_backup=1; fi
  fi
  if [[ -f "$COMPOSE_FILE" ]]; then
    if [[ ! -f "$last_comp" ]] || ! cmp -s "$COMPOSE_FILE" "$last_comp"; then need_backup=1; fi
  fi
  if [[ -f "$CADDY_FILE" ]]; then
    if [[ ! -f "$last_caddy" ]] || ! cmp -s "$CADDY_FILE" "$last_caddy"; then need_backup=1; fi
  fi

  if (( need_backup )); then
    hdr "Backup existing config"
    local BACKUP_DIR="$SCRIPT_DIR/backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    [[ -f "$ENV_FILE" ]]     && cp "$ENV_FILE"     "$BACKUP_DIR/.env"
    [[ -f "$COMPOSE_FILE" ]] && cp "$COMPOSE_FILE" "$BACKUP_DIR/docker-compose.yml"
    [[ -f "$CADDY_FILE" ]]   && cp "$CADDY_FILE"   "$BACKUP_DIR/Caddyfile"
    ok "Backed up to $BACKUP_DIR"

    # Keep only the latest N backups
    local all=( $(ls -1dt "$SCRIPT_DIR"/backup_* 2>/dev/null) )
    if (( ${#all[@]} > KEEP_BACKUPS )); then
      for ((i=KEEP_BACKUPS; i<${#all[@]}; i++)); do rm -rf "${all[$i]}"; done
      info "Pruned old backups; kept last $KEEP_BACKUPS"
    fi
  else
    info "No config change → skipping backup"
  fi
}



# ---------------- Registry login (optional) ----------------
registry_login_prompt(){
  hdr "Docker Registry"
  USE_REG="$(ask_yn "Use a PRIVATE registry? (y/N): " N)"
  if [[ "$USE_REG" == "y" ]]; then
    while :; do
      read -p "Registry URL (e.g. registry.example.com) [docker.io]: " REGISTRY_URL; REGISTRY_URL=${REGISTRY_URL:-docker.io}
      read -p "Registry username: " REG_USER
      read -s -p "Registry password: " REG_PASS; echo
      if echo "$REG_PASS" | docker login "$REGISTRY_URL" -u "$REG_USER" --password-stdin; then
        ok "Logged in to $REGISTRY_URL"
        break
      else
        err "Login failed for $REGISTRY_URL"
        TRY="$(ask_yn "Try again? (y/N): " N)"
        if [[ "$TRY" != "y" ]]; then
          warn "Skipping registry login"
          REGISTRY_URL=""; REG_USER=""; REG_PASS=""
          break
        fi
      fi
    done
  else
    REGISTRY_URL=""; REG_USER=""; REG_PASS=""
    info "Using public images or already-logged-in registry"
  fi
}
choose_topology_and_role(){
  hdr "Topologies"
  cat <<EOF
  1) Single-node (all)
  2) Two-node (Edge+App | Data)
  3) Three-node (Edge | App | Data/Admin)
EOF
  topo="$(ask_int_in_range 'Choose [1]: ' 1 1 3)"

  case "$topo" in
    1)
      hdr "Role for THIS server"
    echo "  1) all-in-one"
    r="$(ask_int_in_range 'Choice [1]: ' 1 1 1)"
      ROLE="all"
  RUN_LOCAL_DATA="y"      # data on this node
      ;;
    2)
      hdr "Role for THIS server"
      cat <<EO2
  1) edge+app  (API/UI services; data external)
  2) data      (Postgres/RabbitMQ/Redis only)
EO2
      r="$(ask_int_in_range 'Choice [1]: ' 1 1 2)"
      if [[ "$r" == "2" ]]; then
        ROLE="data"
        RUN_LOCAL_DATA="y"
      else
  ROLE="edge-app"
  RUN_LOCAL_DATA="n"    # external data
      fi
      ;;
    3)
      hdr "Role for THIS server"
      cat <<EO3
  1) edge      (Caddy/ingress only)
  2) app       (API/UI/processor/worker/jobs; data external)
  3) data      (Postgres/RabbitMQ/Redis only)
EO3
      r="$(ask_int_in_range 'Choice [1]: ' 1 1 3)"
      case "$r" in
        3) ROLE="data"; RUN_LOCAL_DATA="y" ;;
        2) ROLE="app";  RUN_LOCAL_DATA="n" ;;
        *) ROLE="edge"; RUN_LOCAL_DATA="n" ;;
      esac
      ;;
    *) ROLE="all"; RUN_LOCAL_DATA="y" ;;
  esac

  ok "Preset selected → topology=$topo role=$ROLE"
}

# ---------------- Collect config ----------------
collect_config(){
  hdr "Base Configuration"
  read -p "Project name [digitalbot]: " COMPOSE_PROJECT_NAME; COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME:-digitalbot}

  # Domains for app — separate from REGISTRY
  DOMAIN="$(ask_required 'Main domain (e.g. example.com): ')"
  read -p "Client subdomain [client]: " CLIENT_SUB; CLIENT_SUB=${CLIENT_SUB:-client}
  CLIENT_APP_DOMAIN="$CLIENT_SUB.$DOMAIN"

  # --- ACME email; default to admin@domain if not provided elsewhere ---
  if grep -q '^ACME_EMAIL=' "$ENV_FILE" 2>/dev/null; then
    ACME_EMAIL="$(grep -E '^ACME_EMAIL=' "$ENV_FILE" | cut -d= -f2-)"
  else
    ACME_EMAIL="admin@${DOMAIN}"
  fi

# Data hosts depend on ROLE / RUN_LOCAL_DATA (set in choose_topology_and_role)
if [[ "${RUN_LOCAL_DATA}" =~ ^[yY]$ ]]; then
  POSTGRES_HOST="postgres"
  RABBITMQ_HOST="rabbitmq"
  REDIS_HOST="redis"
else
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
  # --- Edge / Caddy: decide automatically from ROLE (no prompt) ---
  case "$ROLE" in
    edge|all|edge-app)
      ENABLE_CADDY="y"
      info "Caddy auto-enabled for role '$ROLE'"
      ;;
    app|data|*)
      ENABLE_CADDY="n"
      info "Caddy auto-disabled for role '$ROLE'"
      ;;
  esac

  # Sizing with a SINGLE number
  hdr "Sizing / Autoscale (based on active users)"
  ACTIVE="$(ask_int_in_range 'Active users at peak (concurrent) [10000]: ' 10000 1 10000000)"
  read WEB_REPL PROCESSER_REPLICAS ORDER_WORKER_REPLICAS < <(calc_replicas_from_active "$ACTIVE")
  info "Replicas → webapp=${WEB_REPL}, processor=${PROCESSER_REPLICAS}, worker=${ORDER_WORKER_REPLICAS}"

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
ACME_EMAIL=${ACME_EMAIL}

# Replicas
WEBAPP_REPLICAS=${WEB_REPL}
PROCESSER_REPLICAS=${PROCESSER_REPLICAS}
ORDER_WORKER_REPLICAS=${ORDER_WORKER_REPLICAS}

# Optional admin domains (only set if you really plan to expose):
# Uncomment or set interactively if you need them public.
# RABBITMQ_DOMAIN=rabbitmq.${DOMAIN}
# PGADMIN_DOMAIN=pgadmin.${DOMAIN}
# REDISINSIGHT_DOMAIN=redis.${DOMAIN}
# PORTAINER_DOMAIN=portainer.${DOMAIN}
EOF
  chmod 600 "$ENV_FILE"; ok ".env ready → $ENV_FILE"

  # DNS sanity checks (non-blocking)
  dns_warn "$DOMAIN"
  dns_warn "$CLIENT_APP_DOMAIN"
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
    profiles: ["app"]

  client-app:
    image: ${CLIENT_APP_IMAGE}
    restart: unless-stopped
    deploy:
      resources:
        limits: { cpus: "0.5", memory: "256M" }
    networks: [ digitalbot_web ]
    profiles: ["app"]

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
    profiles: ["app"]

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
    profiles: ["app"]

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
    profiles: ["app"]

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
    environment:
      - DOMAIN=${DOMAIN}
      - CLIENT_APP_DOMAIN=${CLIENT_APP_DOMAIN}
      - ACME_EMAIL=${ACME_EMAIL}
      - RABBITMQ_DOMAIN=${RABBITMQ_DOMAIN}
      - PGADMIN_DOMAIN=${PGADMIN_DOMAIN}
      - REDISINSIGHT_DOMAIN=${REDISINSIGHT_DOMAIN}
      - PORTAINER_DOMAIN=${PORTAINER_DOMAIN}
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
  if [[ ! "$(grep -E '^ENABLE_CADDY=' "$ENV_FILE" | cut -d= -f2)" =~ ^[yY]$ ]]; then
    warn "Caddy disabled → skipping Caddyfile"
    return 0
  fi

  # Load env for templating
  source "$ENV_FILE"

  # Build site blocks dynamically
  caddy_conf=$(
    cat <<'HDR'
{
  email {$ACME_EMAIL}
  # acme_ca https://acme-staging-v02.api.letsencrypt.org/directory  # <- enable for testing only
}
HDR
  )

  # Core sites – always present
  caddy_conf+="
{$DOMAIN} {
  encode zstd gzip
  reverse_proxy webapp:8080
}
{$CLIENT_APP_DOMAIN} {
  encode zstd gzip
  reverse_proxy client-app:80
}
"

  # Optional admin UIs (only if variable is non-empty and service likely exists)
  # RabbitMQ UI
  if [[ -n "${RABBITMQ_DOMAIN:-}" && "${RUN_LOCAL_DATA:-y}" =~ ^[yY]$ ]]; then
    caddy_conf+="
{$RABBITMQ_DOMAIN} {
  encode zstd gzip
  reverse_proxy rabbitmq:15672
}
"
  fi

  # (Examples to extend later)
  if [[ -n "${PGADMIN_DOMAIN:-}" ]]; then
    caddy_conf+="
{$PGADMIN_DOMAIN} {
  encode zstd gzip
  reverse_proxy pgadmin:80
}
"
  fi
  if [[ -n "${REDISINSIGHT_DOMAIN:-}" ]]; then
    caddy_conf+="
{$REDISINSIGHT_DOMAIN} {
  encode zstd gzip
  reverse_proxy redisinsight:8001
}
"
  fi
  if [[ -n "${PORTAINER_DOMAIN:-}" ]]; then
    caddy_conf+="
{$PORTAINER_DOMAIN} {
  encode zstd gzip
  reverse_proxy portainer:9000
}
"
  fi

  echo "$caddy_conf" > "$CADDY_FILE"
  ok "Caddyfile → $CADDY_FILE"
}

# ---- place this ABOVE configure_backup() ----
write_backup_script(){
  cat >"$BACKUP_SCRIPT"<<'EOS'
#!/usr/bin/env bash
set -euo pipefail
ENV_FILE="$(dirname "$0")/../.env"; source "$ENV_FILE"
STAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="$(dirname "$0")/../backups"; mkdir -p "$OUTDIR"
FILE="${OUTDIR}/pg_${POSTGRES_DB}_${STAMP}.sql.gz"

if [[ "${RUN_LOCAL_DATA:-y}" =~ ^[yY]$ ]]; then
  echo "[INFO] dumping local ${POSTGRES_DB} via compose exec…"
  docker compose -f "$(dirname "$0")/../docker-compose.yml" exec -T postgres \
    pg_dump -U "${POSTGRES_USER}" "${POSTGRES_DB}" | gzip > "$FILE"
else
  echo "[INFO] dumping remote ${POSTGRES_DB} from host ${POSTGRES_HOST}…"
  docker run --rm --network host \
    -e PGPASSWORD="${POSTGRES_PASSWORD}" \
    postgres:16-alpine \
    sh -c 'pg_dump -h '"${POSTGRES_HOST}"' -U '"${POSTGRES_USER}"' '"${POSTGRES_DB}"'' | gzip > "$FILE"
fi

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

  T="$(ask_yn "Enable Telegram delivery? (y/N): " N)"
  if [[ "$T" == "y" ]]; then
    read -p "TELEGRAM_BOT_TOKEN: " TB
    read -p "TELEGRAM_CHAT_ID: " TC
    if [[ -n "$TB" && -n "$TC" ]]; then
      {
        grep -q '^TELEGRAM_BOT_TOKEN=' "$ENV_FILE" && sed -i "s|^TELEGRAM_BOT_TOKEN=.*|TELEGRAM_BOT_TOKEN=${TB}|" "$ENV_FILE" || echo "TELEGRAM_BOT_TOKEN=${TB}" >> "$ENV_FILE"
        grep -q '^TELEGRAM_CHAT_ID=' "$ENV_FILE"  && sed -i "s|^TELEGRAM_CHAT_ID=.*|TELEGRAM_CHAT_ID=${TC}|" "$ENV_FILE"  || echo "TELEGRAM_CHAT_ID=${TC}"  >> "$ENV_FILE"
      }
      ok "Telegram delivery configured"
    else
      warn "Telegram token/chat id empty → skipping Telegram delivery"
    fi
  fi

  C="$(ask_yn "Create cron job for backups? (y/N): " N)"
  if [[ "$C" == "y" ]]; then
    HRS="$(ask_int_in_range 'Backup every how many hours? [6]: ' 6 1 24)"
    MIN=$(( RANDOM % 60 ))
    if [[ "$HRS" -eq 1 ]]; then
      CRON_EXPR="${MIN} * * * * ${BACKUP_SCRIPT} >/dev/null 2>&1"
    else
      CRON_EXPR="${MIN} */${HRS} * * * ${BACKUP_SCRIPT} >/dev/null 2>&1"
    fi
    ( crontab -l 2>/dev/null | grep -v "$BACKUP_SCRIPT" ; echo "$CRON_EXPR" ) | crontab -
    ok "Cron installed: every ${HRS}h at minute ${MIN}"
  fi
}



# --- DB access open/close (Postgres publish port) ---
ensure_pg_override(){
  mkdir -p "$OPS_DIR"
  cat > "$OPS_DIR/pg-open.override.yml" <<'YML'
services:
  postgres:
    ports:
      - "${POSTGRES_BIND_ADDR:-0.0.0.0}:${POSTGRES_PUBLIC_PORT:-5432}:5432"
YML
}

ufw_allow(){
  local port="$1" cidr="$2"
  if command -v ufw >/dev/null 2>&1; then
    sudo ufw allow from "$cidr" to any port "$port" proto tcp || true
  fi
}
ufw_delete_rule(){
  local port="$1" cidr="$2"
  if command -v ufw >/dev/null 2>&1; then
    # Soft delete: ignore if rule does not exist
    sudo ufw delete allow from "$cidr" to any port "$port" proto tcp 2>/dev/null || true
  fi
}

db_access_open(){
  hdr "Open Postgres externally (temporary)"
  source "$ENV_FILE"
  if [[ ! "${RUN_LOCAL_DATA:-y}" =~ ^[yY]$ ]]; then
    err "Local Postgres is not enabled on this node (RUN_LOCAL_DATA=n)."
    return 1
  fi

  # Port and bind address
  read -p "Public port to expose [${POSTGRES_PUBLIC_PORT:-5432}]: " PPORT; PPORT=${PPORT:-${POSTGRES_PUBLIC_PORT:-5432}}
  read -p "Bind address [${POSTGRES_BIND_ADDR:-0.0.0.0}] (use 127.0.0.1 to bind local only): " BADDR; BADDR=${BADDR:-${POSTGRES_BIND_ADDR:-0.0.0.0}}
  # Optional IP restriction
  read -p "Allowed CIDR (optional, e.g. 203.0.113.5/32). Leave empty to allow all: " CIDR

  # Persist in .env
  grep -q '^POSTGRES_PUBLIC_PORT=' "$ENV_FILE" && sed -i "s/^POSTGRES_PUBLIC_PORT=.*/POSTGRES_PUBLIC_PORT=${PPORT}/" "$ENV_FILE" || echo "POSTGRES_PUBLIC_PORT=${PPORT}" >> "$ENV_FILE"
  grep -q '^POSTGRES_BIND_ADDR='  "$ENV_FILE" && sed -i "s/^POSTGRES_BIND_ADDR=.*/POSTGRES_BIND_ADDR=${BADDR}/"   "$ENV_FILE" || echo "POSTGRES_BIND_ADDR=${BADDR}"   >> "$ENV_FILE"
  if [[ -n "$CIDR" ]]; then
    grep -q '^POSTGRES_ALLOWED_CIDR=' "$ENV_FILE" && sed -i "s|^POSTGRES_ALLOWED_CIDR=.*|POSTGRES_ALLOWED_CIDR=${CIDR}|" "$ENV_FILE" || echo "POSTGRES_ALLOWED_CIDR=${CIDR}" >> "$ENV_FILE"
  fi

  ensure_pg_override

  # Recreate only postgres with override (data profile)
  docker compose -f "$COMPOSE_FILE" -f "$OPS_DIR/pg-open.override.yml" --profile data up -d postgres

  # Firewall (optional)
  if [[ -n "$CIDR" ]]; then
    info "Applying ufw rule to allow ${CIDR} on ${PPORT}/tcp (if ufw is present)…"
    ufw_allow "$PPORT" "$CIDR"
  fi

  # Show connection info
  HOST_SHOW="$(hostname -I 2>/dev/null | awk '{print $1}')"
  echo
  ok "Postgres is now exposed."
  echo "Use this connection in DataGrip / psql:"
  echo "  Host: ${HOST_SHOW}   Port: ${PPORT}"
  echo "  DB:   ${POSTGRES_DB}  User: ${POSTGRES_USER}"
  echo "  SSL:  disable (unless you configured TLS on Postgres)"
  echo
  warn "Remember to CLOSE access after testing."
}

db_access_close(){
  hdr "Close Postgres external access"
  source "$ENV_FILE"

  # Remove ufw rule if previously set
  if grep -q '^POSTGRES_ALLOWED_CIDR=' "$ENV_FILE"; then
    CIDR="$(grep -E '^POSTGRES_ALLOWED_CIDR=' "$ENV_FILE" | cut -d= -f2-)"
    PPORT="$(grep -E '^POSTGRES_PUBLIC_PORT=' "$ENV_FILE" | cut -d= -f2-)"
    [[ -n "$CIDR" && -n "$PPORT" ]] && ufw_delete_rule "$PPORT" "$CIDR"
  fi

  # Bring up without override → published port is removed
  docker compose -f "$COMPOSE_FILE" --profile data up -d postgres

  ok "External access closed."
}

# ---------------- Compose wrapper ----------------
compose_cmd(){
  local profiles=()
  case "${ROLE:-}" in
    all|edge-app|app) profiles+=( --profile app ) ;;
  esac
  if [[ "${ROLE:-}" == "all" || "${ROLE:-}" == "data" || "$(grep -E '^RUN_LOCAL_DATA=' "$ENV_FILE" 2>/dev/null | cut -d= -f2)" =~ ^[yY]$ ]]; then
    profiles+=( --profile data )
  fi
  if [[ "${ROLE:-}" == "edge" || "$(grep -E '^ENABLE_CADDY=' "$ENV_FILE" 2>/dev/null | cut -d= -f2)" =~ ^[yY]$ ]]; then
    profiles+=( --profile caddy )
  fi
  docker compose -f "$COMPOSE_FILE" "${profiles[@]}" "$@"
}


# ---------------- Actions ----------------
do_install(){
  ensure_packages
  backup_existing
  registry_login_prompt
  choose_topology_and_role     # added
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
  hdr "Scale (single input)"
  source "$ENV_FILE"

  # Single question for sizing
  ACTIVE="$(ask_int_in_range "Active users at peak (concurrent) [${ACTIVE_USERS_LAST:-10000}]: " ${ACTIVE_USERS_LAST:-10000} 1 10000000)"

  # Automatic calculation (fixed RPM 6)
  read WEB PRC WRK < <(calc_replicas_from_active "$ACTIVE")

  info "Calculated replicas → webapp=${WEB}, processor=${PRC}, worker=${WRK}"

  # Persist in .env
  grep -q '^ACTIVE_USERS_LAST=' "$ENV_FILE" && \
    sed -i "s/^ACTIVE_USERS_LAST=.*/ACTIVE_USERS_LAST=${ACTIVE}/" "$ENV_FILE" || \
    echo "ACTIVE_USERS_LAST=${ACTIVE}" >> "$ENV_FILE"

  sed -i "s/^WEBAPP_REPLICAS=.*/WEBAPP_REPLICAS=${WEB}/" "$ENV_FILE" || true
  sed -i "s/^PROCESSER_REPLICAS=.*/PROCESSER_REPLICAS=${PRC}/" "$ENV_FILE" || true
  sed -i "s/^ORDER_WORKER_REPLICAS=.*/ORDER_WORKER_REPLICAS=${WRK}/" "$ENV_FILE" || true

  # Apply scaling
  compose_cmd up -d --scale webapp="$WEB" --scale processor="$PRC" --scale worker="$WRK"
  ok "Scaled successfully"

  # Gentle bounce (optional)
  BNC="$(ask_yn "Do gentle bounce of webapp (sequential restart)? (y/N): " N)"
  if [[ "$BNC" == "y" ]]; then
    gentle_bounce_service "webapp"
  fi
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
6) DB access (open/close Postgres)
q) Quit
MENU
  read -p "Choice: " ch
  case "$ch" in
    1) do_install ;;
    2) do_update ;;
    3) do_scale ;;
    4) configure_backup ;;
    5) do_registry ;;
    6)
       # Disable when data is external
       if [[ -f "$ENV_FILE" ]] && grep -q '^RUN_LOCAL_DATA=n' "$ENV_FILE"; then
         err "DB access controls are disabled because RUN_LOCAL_DATA=n (external DB)."
       else
         echo "a) Open Postgres access"
         echo "b) Close Postgres access"
         read -p "Choose [a/b]: " dch
         if [[ "$dch" == "a" ]]; then db_access_open; else db_access_close; fi
       fi
       ;;
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
