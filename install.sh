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
    [[ "$v" =~ ^[0-9]+$ ]] && (( v>=lo && v<=hi )) && { printf "%s" "$v"; return 0; }
    err "Enter an integer between $lo and $hi"
  done
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
  read -p "Use a PRIVATE registry? (y/N): " USE_REG; USE_REG=${USE_REG:-N}
  if [[ "$USE_REG" =~ ^[yY]$ ]]; then
    while :; do
      read -p "Registry URL (e.g. registry.example.com) [docker.io]: " REGISTRY_URL; REGISTRY_URL=${REGISTRY_URL:-docker.io}
      read -p "Registry username: " REG_USER
      read -s -p "Registry password: " REG_PASS; echo
      if echo "$REG_PASS" | docker login "$REGISTRY_URL" -u "$REG_USER" --password-stdin; then
        ok "Logged in to $REGISTRY_URL"
        break
      else
        err "Login failed for $REGISTRY_URL"
        read -p "Try again? (y/N): " TRY; TRY=${TRY:-N}
        if [[ ! "$TRY" =~ ^[yY]$ ]]; then
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
  read -p "Choose [1]: " topo; topo=${topo:-1}

  case "$topo" in
    1)
      hdr "Role for THIS server"
      echo "  1) all-in-one"
      read -p "Choice [1]: " r; r=${r:-1}
      ROLE="all"
  RUN_LOCAL_DATA="y"      # data on this node
      ;;
    2)
      hdr "Role for THIS server"
      cat <<EO2
  1) edge+app  (API/UI services; data external)
  2) data      (Postgres/RabbitMQ/Redis only)
EO2
      read -p "Choice [1]: " r; r=${r:-1}
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
      read -p "Choice [1]: " r; r=${r:-1}
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
# Decide Caddy default based on ROLE
case "$ROLE" in
  edge)       ENABLE_CADDY="y" ;;         # required on edge
  edge-app)   ENABLE_CADDY=""  ;;         # ask user
  all)        ENABLE_CADDY=""  ;;         # ask user
  app|data)   ENABLE_CADDY="n" ;;         # default off
esac

  # Caddy
hdr "Edge / Caddy"
if [[ "$ROLE" == "edge" ]]; then
  info "Caddy enabled automatically for edge role"
  ENABLE_CADDY="y"
else
  if [[ -z "${ENABLE_CADDY}" ]]; then
    read -p "Enable Caddy on THIS node? (y/N): " ENABLE_CADDY; ENABLE_CADDY=${ENABLE_CADDY:-N}
  else
    info "Caddy default for role '$ROLE' → ${ENABLE_CADDY^^}"
  fi
fi

  # Sizing with a SINGLE number
  hdr "Sizing / Autoscale (based on active users)"
  read -p "Active users at peak (concurrent) [10000]: " ACTIVE; ACTIVE=${ACTIVE:-10000}
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

  read -p "Enable Telegram delivery? (y/N): " T; T=${T:-N}
  if [[ "$T" =~ ^[yY]$ ]]; then
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

  read -p "Create cron job for backups? (y/N): " C; C=${C:-N}
  if [[ "$C" =~ ^[yY]$ ]]; then
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



# ---------------- Compose wrapper ----------------
compose_cmd(){
  local profiles=()
  # app profile?
  case "${ROLE:-}" in
    all|edge-app|app) profiles+=( --profile app ) ;;
  esac
  # data / caddy profiles?
  if [[ -f "$ENV_FILE" ]]; then
    # Also read from .env, but ROLE still influences decisions
    local run_data_env="$(grep -E '^RUN_LOCAL_DATA=' "$ENV_FILE" | cut -d= -f2 || true)"
    if [[ "${ROLE:-}" == "all" || "${ROLE:-}" == "data" || "$run_data_env" =~ ^[yY]$ ]]; then
      profiles+=( --profile data )
    fi
    local en_caddy_env="$(grep -E '^ENABLE_CADDY=' "$ENV_FILE" | cut -d= -f2 || true)"
    if [[ "${ROLE:-}" == "edge" || "$en_caddy_env" =~ ^[yY]$ ]]; then
      profiles+=( --profile caddy )
    fi
  else
    # Before .env exists: if role=edge, bring up caddy too
    [[ "${ROLE:-}" == "edge" ]] && profiles+=( --profile caddy )
    [[ "${ROLE:-}" == "data" || "${ROLE:-}" == "all" ]] && profiles+=( --profile data )
    [[ "${ROLE:-}" == "all" || "${ROLE:-}" == "edge-app" || "${ROLE:-}" == "app" ]] && profiles+=( --profile app )
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
  read -p "Active users at peak (concurrent) [${ACTIVE_USERS_LAST:-10000}]: " ACTIVE
  ACTIVE="${ACTIVE:-${ACTIVE_USERS_LAST:-10000}}"

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
  read -p "Do gentle bounce of webapp (sequential restart)? (y/N): " BNC; BNC=${BNC:-N}
  if [[ "$BNC" =~ ^[yY]$ ]]; then
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
