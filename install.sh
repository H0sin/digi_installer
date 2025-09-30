#!/bin/bash

# Digital Bot Infrastructure - Professional Installation Script
# Version: 1.0.0
# This script automates the installation and configuration of the Digital Bot infrastructure

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
ENV_EXAMPLE="${SCRIPT_DIR}/.env.example"
BACKUP_DIR="${SCRIPT_DIR}/backup_$(date +%Y%m%d_%H%M%S)"

# Log functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_header() {
    echo -e "\n${BOLD}${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════${NC}\n"
}

# Display banner
show_banner() {
    clear
    echo -e "${BLUE}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║        Digital Bot Infrastructure Installation Script        ║
║                        Version 1.0.0                          ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_warning "This script should not be run as root. Please run as a regular user with sudo privileges."
        read -p "Do you want to continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Check system requirements
check_system_requirements() {
    log_header "Checking System Requirements"
    
    # Check OS
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        log_info "Operating System: $NAME $VERSION"
    fi
    
    # Check CPU cores
    CPU_CORES=$(nproc)
    log_info "CPU Cores: $CPU_CORES"
    if [ "$CPU_CORES" -lt 2 ]; then
        log_warning "Minimum 2 CPU cores recommended. Current: $CPU_CORES"
    fi
    
    # Check RAM
    TOTAL_RAM=$(free -h | awk '/^Mem:/ {print $2}')
    TOTAL_RAM_MB=$(free -m | awk '/^Mem:/ {print $2}')
    log_info "Total RAM: $TOTAL_RAM"
    if [ "$TOTAL_RAM_MB" -lt 2048 ]; then
        log_warning "Minimum 2GB RAM recommended. Current: $TOTAL_RAM"
    fi
    
    # Check disk space
    AVAILABLE_SPACE=$(df -h "$SCRIPT_DIR" | awk 'NR==2 {print $4}')
    log_info "Available disk space: $AVAILABLE_SPACE"
    
    log_success "System requirements check completed"
}

# Check and install Docker
check_install_docker() {
    log_header "Checking Docker Installation"
    
    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version)
        log_success "Docker is already installed: $DOCKER_VERSION"
        
        # Check if Docker service is running
        if systemctl is-active --quiet docker; then
            log_success "Docker service is running"
        else
            log_warning "Docker service is not running"
            read -p "Do you want to start Docker service? (Y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                sudo systemctl start docker
                sudo systemctl enable docker
                log_success "Docker service started and enabled"
            fi
        fi
    else
        log_warning "Docker is not installed"
        read -p "Do you want to install Docker? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            log_info "Installing Docker..."
            
            # Update package index
            sudo apt-get update
            
            # Install prerequisites
            sudo apt-get install -y \
                ca-certificates \
                curl \
                gnupg \
                lsb-release
            
            # Add Docker's official GPG key
            sudo mkdir -p /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            
            # Set up the repository
            echo \
              "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
              $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            
            # Install Docker Engine
            sudo apt-get update
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            
            # Add current user to docker group
            sudo usermod -aG docker $USER
            
            log_success "Docker installed successfully"
            log_warning "You may need to log out and back in for group changes to take effect"
        else
            log_error "Docker is required. Installation aborted."
            exit 1
        fi
    fi
    
    # Check if user is in docker group
    if ! groups | grep -q docker; then
        log_warning "User is not in docker group"
        read -p "Do you want to add current user to docker group? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            sudo usermod -aG docker $USER
            log_success "User added to docker group"
            log_warning "You need to log out and back in for changes to take effect"
        fi
    fi
}

# Check Docker Compose
check_docker_compose() {
    log_header "Checking Docker Compose"
    
    if docker compose version &> /dev/null; then
        COMPOSE_VERSION=$(docker compose version)
        log_success "Docker Compose is available: $COMPOSE_VERSION"
    else
        log_error "Docker Compose is not available"
        log_info "Please ensure Docker Compose plugin is installed"
        exit 1
    fi
}

# Backup existing configuration
backup_existing_config() {
    if [ -f "$ENV_FILE" ]; then
        log_header "Backing Up Existing Configuration"
        
        mkdir -p "$BACKUP_DIR"
        cp "$ENV_FILE" "$BACKUP_DIR/.env"
        
        if [ -f "$SCRIPT_DIR/docker-compose.yml" ]; then
            cp "$SCRIPT_DIR/docker-compose.yml" "$BACKUP_DIR/docker-compose.yml"
        fi
        
        log_success "Configuration backed up to: $BACKUP_DIR"
    fi
}

# Interactive service selection
select_services() {
    log_header "Service Configuration"
    
    echo -e "${BOLD}Select which services to deploy on this server:${NC}\n"
    
    # Database services
    read -p "Install PostgreSQL database? (Y/n): " INSTALL_POSTGRES
    INSTALL_POSTGRES=${INSTALL_POSTGRES:-Y}
    
    if [[ $INSTALL_POSTGRES =~ ^[Yy]$ ]]; then
        read -p "Install PgAdmin (PostgreSQL web interface)? (Y/n): " INSTALL_PGADMIN
        INSTALL_PGADMIN=${INSTALL_PGADMIN:-Y}
    else
        INSTALL_PGADMIN="N"
    fi
    
    # Message queue
    read -p "Install RabbitMQ message broker? (Y/n): " INSTALL_RABBITMQ
    INSTALL_RABBITMQ=${INSTALL_RABBITMQ:-Y}
    
    # Cache
    read -p "Install Redis cache? (Y/n): " INSTALL_REDIS
    INSTALL_REDIS=${INSTALL_REDIS:-Y}
    
    if [[ $INSTALL_REDIS =~ ^[Yy]$ ]]; then
        read -p "Install Redis Insight (Redis web interface)? (Y/n): " INSTALL_REDIS_INSIGHT
        INSTALL_REDIS_INSIGHT=${INSTALL_REDIS_INSIGHT:-Y}
    else
        INSTALL_REDIS_INSIGHT="N"
    fi
    
    # Storage
    read -p "Install MinIO object storage? (Y/n): " INSTALL_MINIO
    INSTALL_MINIO=${INSTALL_MINIO:-Y}
    
    # Management tools
    read -p "Install Portainer (Docker management UI)? (Y/n): " INSTALL_PORTAINER
    INSTALL_PORTAINER=${INSTALL_PORTAINER:-Y}
    
    # Application services
    read -p "Install main web application? (Y/n): " INSTALL_WEBAPP
    INSTALL_WEBAPP=${INSTALL_WEBAPP:-Y}
    
    read -p "Install client application (React frontend)? (Y/n): " INSTALL_CLIENT
    INSTALL_CLIENT=${INSTALL_CLIENT:-Y}
    
    read -p "Install processor service? (Y/n): " INSTALL_PROCESSOR
    INSTALL_PROCESSOR=${INSTALL_PROCESSOR:-Y}
    
    if [[ $INSTALL_PROCESSOR =~ ^[Yy]$ ]]; then
        read -p "Number of processor replicas (1-10) [5]: " PROCESSOR_REPLICAS
        PROCESSOR_REPLICAS=${PROCESSOR_REPLICAS:-5}
    fi
    
    read -p "Install order worker service? (Y/n): " INSTALL_WORKER
    INSTALL_WORKER=${INSTALL_WORKER:-Y}
    
    if [[ $INSTALL_WORKER =~ ^[Yy]$ ]]; then
        read -p "Number of order worker replicas (1-10) [2]: " WORKER_REPLICAS
        WORKER_REPLICAS=${WORKER_REPLICAS:-2}
    fi
    
    read -p "Install jobs service? (Y/n): " INSTALL_JOBS
    INSTALL_JOBS=${INSTALL_JOBS:-Y}
    
    read -p "Install Caddy reverse proxy? (Y/n): " INSTALL_CADDY
    INSTALL_CADDY=${INSTALL_CADDY:-Y}
    
    log_success "Service selection completed"
}

# Collect environment variables
collect_env_variables() {
    log_header "Environment Configuration"
    
    echo -e "${BOLD}Please provide the following configuration values:${NC}\n"
    
    # Project name
    read -p "Project name [digitalbot]: " PROJECT_NAME
    PROJECT_NAME=${PROJECT_NAME:-digitalbot}
    
    # Domain configuration
    log_info "Domain Configuration"
    read -p "Main domain (e.g., example.com): " DOMAIN
    while [ -z "$DOMAIN" ]; do
        log_error "Domain is required"
        read -p "Main domain (e.g., example.com): " DOMAIN
    done
    
    read -p "Client app subdomain [client]: " CLIENT_SUBDOMAIN
    CLIENT_SUBDOMAIN=${CLIENT_SUBDOMAIN:-client}
    CLIENT_APP_DOMAIN="${CLIENT_SUBDOMAIN}.${DOMAIN}"
    
    read -p "Traefik dashboard subdomain [traefik]: " TRAEFIK_SUBDOMAIN
    TRAEFIK_SUBDOMAIN=${TRAEFIK_SUBDOMAIN:-traefik}
    TRAEFIK_DOMAIN="${TRAEFIK_SUBDOMAIN}.${DOMAIN}"
    
    read -p "Portainer subdomain [portainer]: " PORTAINER_SUBDOMAIN
    PORTAINER_SUBDOMAIN=${PORTAINER_SUBDOMAIN:-portainer}
    PORTAINER_DOMAIN="${PORTAINER_SUBDOMAIN}.${DOMAIN}"
    
    read -p "RabbitMQ subdomain [rabbitmq]: " RABBITMQ_SUBDOMAIN
    RABBITMQ_SUBDOMAIN=${RABBITMQ_SUBDOMAIN:-rabbitmq}
    RABBITMQ_DOMAIN="${RABBITMQ_SUBDOMAIN}.${DOMAIN}"
    
    read -p "PgAdmin subdomain [pgadmin]: " PGADMIN_SUBDOMAIN
    PGADMIN_SUBDOMAIN=${PGADMIN_SUBDOMAIN:-pgadmin}
    PGADMIN_DOMAIN="${PGADMIN_SUBDOMAIN}.${DOMAIN}"
    
    read -p "Redis Insight subdomain [redis]: " REDIS_SUBDOMAIN
    REDIS_SUBDOMAIN=${REDIS_SUBDOMAIN:-redis}
    REDISINSIGHT_DOMAIN="${REDIS_SUBDOMAIN}.${DOMAIN}"
    
    read -p "MinIO Console subdomain [minio]: " MINIO_SUBDOMAIN
    MINIO_SUBDOMAIN=${MINIO_SUBDOMAIN:-minio}
    MINIO_DOMAIN="${MINIO_SUBDOMAIN}.${DOMAIN}"
    
    read -p "MinIO Files subdomain [files]: " FILES_SUBDOMAIN
    FILES_SUBDOMAIN=${FILES_SUBDOMAIN:-files}
    FILES_DOMAIN="${FILES_SUBDOMAIN}.${DOMAIN}"
    
    # SSL/TLS Configuration
    log_info "\nSSL/TLS Configuration"
    read -p "Email for Let's Encrypt certificates: " ACME_EMAIL
    while [ -z "$ACME_EMAIL" ]; do
        log_error "Email is required for Let's Encrypt"
        read -p "Email for Let's Encrypt certificates: " ACME_EMAIL
    done
    
    read -p "Cloudflare DNS API token (optional, for wildcard certs): " CF_DNS_API_TOKEN
    
    # Docker images
    log_info "\nDocker Images Configuration"
    read -p "Main webapp image [docker.${DOMAIN}/digital-web:latest]: " WEBAPP_IMAGE
    WEBAPP_IMAGE=${WEBAPP_IMAGE:-"docker.${DOMAIN}/digital-web:latest"}
    
    read -p "Processor image [docker.${DOMAIN}/digital-processer:latest]: " PROCESSOR_IMAGE
    PROCESSOR_IMAGE=${PROCESSOR_IMAGE:-"docker.${DOMAIN}/digital-processer:latest"}
    
    read -p "Client app image [docker.${DOMAIN}/digital-client:latest]: " CLIENT_APP_IMAGE
    CLIENT_APP_IMAGE=${CLIENT_APP_IMAGE:-"docker.${DOMAIN}/digital-client:latest"}
    
    read -p "Order worker image [docker.${DOMAIN}/digital-order-worker:latest]: " ORDER_WORKER_IMAGE
    ORDER_WORKER_IMAGE=${ORDER_WORKER_IMAGE:-"docker.${DOMAIN}/digital-order-worker:latest"}
    
    read -p "Jobs image [docker.${DOMAIN}/digital-jobs:latest]: " JOBS_IMAGE
    JOBS_IMAGE=${JOBS_IMAGE:-"docker.${DOMAIN}/digital-jobs:latest"}
    
    # Database configuration
    if [[ $INSTALL_POSTGRES =~ ^[Yy]$ ]]; then
        log_info "\nPostgreSQL Configuration"
        read -p "PostgreSQL username [hossein]: " POSTGRES_USER
        POSTGRES_USER=${POSTGRES_USER:-hossein}
        
        read -sp "PostgreSQL password: " POSTGRES_PASSWORD
        echo
        while [ -z "$POSTGRES_PASSWORD" ]; do
            log_error "Password is required"
            read -sp "PostgreSQL password: " POSTGRES_PASSWORD
            echo
        done
        
        read -p "PostgreSQL database name [digitalbot_db]: " POSTGRES_DB
        POSTGRES_DB=${POSTGRES_DB:-digitalbot_db}
    fi
    
    # RabbitMQ configuration
    if [[ $INSTALL_RABBITMQ =~ ^[Yy]$ ]]; then
        log_info "\nRabbitMQ Configuration"
        read -p "RabbitMQ username [hossein]: " RABBITMQ_USER
        RABBITMQ_USER=${RABBITMQ_USER:-hossein}
        
        read -sp "RabbitMQ password: " RABBITMQ_PASSWORD
        echo
        while [ -z "$RABBITMQ_PASSWORD" ]; do
            log_error "Password is required"
            read -sp "RabbitMQ password: " RABBITMQ_PASSWORD
            echo
        done
    fi
    
    # Redis configuration
    if [[ $INSTALL_REDIS =~ ^[Yy]$ ]]; then
        log_info "\nRedis Configuration"
        read -sp "Redis password: " REDIS_PASSWORD
        echo
        while [ -z "$REDIS_PASSWORD" ]; do
            log_error "Password is required"
            read -sp "Redis password: " REDIS_PASSWORD
            echo
        done
    fi
    
    # PgAdmin configuration
    if [[ $INSTALL_PGADMIN =~ ^[Yy]$ ]]; then
        log_info "\nPgAdmin Configuration"
        read -p "PgAdmin email: " PGADMIN_EMAIL
        while [ -z "$PGADMIN_EMAIL" ]; do
            log_error "Email is required"
            read -p "PgAdmin email: " PGADMIN_EMAIL
        done
        
        read -sp "PgAdmin password: " PGADMIN_PASSWORD
        echo
        while [ -z "$PGADMIN_PASSWORD" ]; do
            log_error "Password is required"
            read -sp "PgAdmin password: " PGADMIN_PASSWORD
            echo
        done
    fi
    
    # MinIO configuration
    if [[ $INSTALL_MINIO =~ ^[Yy]$ ]]; then
        log_info "\nMinIO Configuration"
        read -p "MinIO access key [minioadmin]: " MINIO_ACCESS_KEY
        MINIO_ACCESS_KEY=${MINIO_ACCESS_KEY:-minioadmin}
        
        read -sp "MinIO secret key: " MINIO_SECRET_KEY
        echo
        while [ -z "$MINIO_SECRET_KEY" ]; do
            log_error "Secret key is required"
            read -sp "MinIO secret key: " MINIO_SECRET_KEY
            echo
        done
        
        read -p "MinIO bucket name [digitalbot]: " MINIO_BUCKET
        MINIO_BUCKET=${MINIO_BUCKET:-digitalbot}
        
        MINIO_ENDPOINT="minio:9000"
        MINIO_SERVER_URL="https://${FILES_DOMAIN}"
        MINIO_BROWSER_REDIRECT_URL="https://${MINIO_DOMAIN}"
        MINIO_PUBLIC_URL="https://${FILES_DOMAIN}"
        MINIO_REGION="us-east-1"
        MINIO_USE_SSL="false"
        STORAGE_PROVIDER="minio"
    fi
    
    # Telegram Logger (optional)
    log_info "\nTelegram Logger Configuration (Optional)"
    read -p "Enable Telegram logging? (y/N): " ENABLE_TELEGRAM
    if [[ $ENABLE_TELEGRAM =~ ^[Yy]$ ]]; then
        TELEGRAMLOGGER_ENABLED="true"
        read -p "Telegram Bot Token: " TELEGRAMLOGGER_BOTTOKEN
        read -p "Telegram Chat ID: " TELEGRAMLOGGER_CHATID
        read -p "Default Topic ID [19]: " TELEGRAMLOGGER_TOPICS_DEFAULT
        TELEGRAMLOGGER_TOPICS_DEFAULT=${TELEGRAMLOGGER_TOPICS_DEFAULT:-19}
        read -p "Information Topic ID [20]: " TELEGRAMLOGGER_TOPICS_INFORMATION
        TELEGRAMLOGGER_TOPICS_INFORMATION=${TELEGRAMLOGGER_TOPICS_INFORMATION:-20}
        read -p "Warning Topic ID [21]: " TELEGRAMLOGGER_TOPICS_WARNING
        TELEGRAMLOGGER_TOPICS_WARNING=${TELEGRAMLOGGER_TOPICS_WARNING:-21}
        read -p "Error Topic ID [22]: " TELEGRAMLOGGER_TOPICS_ERROR
        TELEGRAMLOGGER_TOPICS_ERROR=${TELEGRAMLOGGER_TOPICS_ERROR:-22}
        read -p "Critical Topic ID [23]: " TELEGRAMLOGGER_TOPICS_CRITICAL
        TELEGRAMLOGGER_TOPICS_CRITICAL=${TELEGRAMLOGGER_TOPICS_CRITICAL:-23}
        read -p "Orders Topic ID [24]: " TELEGRAMLOGGER_TOPICS_ORDERS
        TELEGRAMLOGGER_TOPICS_ORDERS=${TELEGRAMLOGGER_TOPICS_ORDERS:-24}
        read -p "Payments Topic ID [25]: " TELEGRAMLOGGER_TOPICS_PAYMENTS
        TELEGRAMLOGGER_TOPICS_PAYMENTS=${TELEGRAMLOGGER_TOPICS_PAYMENTS:-25}
    else
        TELEGRAMLOGGER_ENABLED="false"
        TELEGRAMLOGGER_BOTTOKEN=""
        TELEGRAMLOGGER_CHATID=""
        TELEGRAMLOGGER_TOPICS_DEFAULT="19"
        TELEGRAMLOGGER_TOPICS_INFORMATION="20"
        TELEGRAMLOGGER_TOPICS_WARNING="21"
        TELEGRAMLOGGER_TOPICS_ERROR="22"
        TELEGRAMLOGGER_TOPICS_CRITICAL="23"
        TELEGRAMLOGGER_TOPICS_ORDERS="24"
        TELEGRAMLOGGER_TOPICS_PAYMENTS="25"
    fi
    
    # Client app configuration
    VITE_BASE_API="https://${DOMAIN}"
    
    log_success "Environment configuration collected"
}

# Generate .env file
generate_env_file() {
    log_header "Generating Environment File"
    
    cat > "$ENV_FILE" << EOF
# === Base Project ===
COMPOSE_PROJECT_NAME=${PROJECT_NAME}
WEBAPP_IMAGE=${WEBAPP_IMAGE}
PROCESSOR_IMAGE=${PROCESSOR_IMAGE}
CLIENT_APP_IMAGE=${CLIENT_APP_IMAGE}
ORDER_WORKER_IMAGE=${ORDER_WORKER_IMAGE}
JOBS_IMAGE=${JOBS_IMAGE}
PROCESSER_REPLICAS=${PROCESSOR_REPLICAS:-5}
ORDER_WORKER_REPLICAS=${WORKER_REPLICAS:-2}


#DOMAINS
DOMAIN=${DOMAIN}
CLIENT_APP_DOMAIN=${CLIENT_APP_DOMAIN}
TRAEFIK_DOMAIN=${TRAEFIK_DOMAIN}
PORTAINER_DOMAIN=${PORTAINER_DOMAIN}
RABBITMQ_DOMAIN=${RABBITMQ_DOMAIN}
PGADMIN_DOMAIN=${PGADMIN_DOMAIN}
REDISINSIGHT_DOMAIN=${REDISINSIGHT_DOMAIN}

#TRAEFIK & AUTH
TRAEFIK_ACME_EMAIL=${ACME_EMAIL}
CF_DNS_API_TOKEN=${CF_DNS_API_TOKEN}
TRAEFIK_DASHBOARD_AUTH="Digitall:\$\$apr1\$\$SHypH7nP\$\$AD8PmYFtlnpuvhSC9EZuT."

#SERVICE CREDENTIALS
POSTGRES_USER=${POSTGRES_USER:-hossein}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-changeme}
POSTGRES_DB=${POSTGRES_DB:-digitalbot_db}

RABBITMQ_USER=${RABBITMQ_USER:-hossein}
RABBITMQ_PASSWORD=${RABBITMQ_PASSWORD:-changeme}

REDIS_PASSWORD=${REDIS_PASSWORD:-changeme}

PGADMIN_EMAIL=${PGADMIN_EMAIL:-admin@example.com}
PGADMIN_PASSWORD=${PGADMIN_PASSWORD:-changeme}

#CLIENT APP
VITE_BASE_API=${VITE_BASE_API}

# === Telegram Logger ===
TELEGRAMLOGGER__ENABLED=${TELEGRAMLOGGER_ENABLED}
TELEGRAMLOGGER__BOTTOKEN=${TELEGRAMLOGGER_BOTTOKEN}
TELEGRAMLOGGER__CHATID=${TELEGRAMLOGGER_CHATID}
TELEGRAMLOGGER__TOPICS__DEFAULT=${TELEGRAMLOGGER_TOPICS_DEFAULT}
TELEGRAMLOGGER__TOPICS__INFORMATION=${TELEGRAMLOGGER_TOPICS_INFORMATION}
TELEGRAMLOGGER__TOPICS__WARNING=${TELEGRAMLOGGER_TOPICS_WARNING}
TELEGRAMLOGGER__TOPICS__ERROR=${TELEGRAMLOGGER_TOPICS_ERROR}
TELEGRAMLOGGER__TOPICS__CRITICAL=${TELEGRAMLOGGER_TOPICS_CRITICAL}
TELEGRAMLOGGER__TOPICS__ORDERS=${TELEGRAMLOGGER_TOPICS_ORDERS}
TELEGRAMLOGGER__TOPICS__PAYMENTS=${TELEGRAMLOGGER_TOPICS_PAYMENTS}

# === MinIO Storage ===
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

EOF
    
    chmod 600 "$ENV_FILE"
    log_success ".env file generated at: $ENV_FILE"
}

# Update Caddyfile based on selected services
update_caddyfile() {
    log_header "Updating Caddyfile"
    
    cat > "$SCRIPT_DIR/Caddyfile" << EOF
EOF
    
    if [[ $INSTALL_WEBAPP =~ ^[Yy]$ ]]; then
        cat >> "$SCRIPT_DIR/Caddyfile" << EOF
${DOMAIN} {
  reverse_proxy webapp:8080
}

EOF
    fi
    
    if [[ $INSTALL_CLIENT =~ ^[Yy]$ ]]; then
        cat >> "$SCRIPT_DIR/Caddyfile" << EOF
${CLIENT_APP_DOMAIN} {
  reverse_proxy client-app:80
}

EOF
    fi
    
    if [[ $INSTALL_PGADMIN =~ ^[Yy]$ ]]; then
        cat >> "$SCRIPT_DIR/Caddyfile" << EOF
${PGADMIN_DOMAIN} {
  reverse_proxy pgadmin:80
}

EOF
    fi
    
    if [[ $INSTALL_PORTAINER =~ ^[Yy]$ ]]; then
        cat >> "$SCRIPT_DIR/Caddyfile" << EOF
${PORTAINER_DOMAIN} {
  reverse_proxy portainer:9000
}

EOF
    fi
    
    if [[ $INSTALL_RABBITMQ =~ ^[Yy]$ ]]; then
        cat >> "$SCRIPT_DIR/Caddyfile" << EOF
${RABBITMQ_DOMAIN} {
  reverse_proxy rabbitmq:15672
}

EOF
    fi
    
    if [[ $INSTALL_REDIS_INSIGHT =~ ^[Yy]$ ]]; then
        cat >> "$SCRIPT_DIR/Caddyfile" << EOF
${REDISINSIGHT_DOMAIN} {
  reverse_proxy redisinsight:8001
}

EOF
    fi
    
    if [[ $INSTALL_MINIO =~ ^[Yy]$ ]]; then
        cat >> "$SCRIPT_DIR/Caddyfile" << EOF
# MinIO Console UI
${MINIO_DOMAIN} {
  reverse_proxy minio:9001
}

# MinIO S3 API for public file URLs
${FILES_DOMAIN} {
  reverse_proxy minio:9000
}
EOF
    fi
    
    log_success "Caddyfile updated"
}

# Validate configuration
validate_configuration() {
    log_header "Validating Configuration"
    
    # Check if .env file exists
    if [ ! -f "$ENV_FILE" ]; then
        log_error ".env file not found"
        return 1
    fi
    
    # Check required variables
    source "$ENV_FILE"
    
    local required_vars=("DOMAIN" "COMPOSE_PROJECT_NAME")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        log_error "Missing required variables: ${missing_vars[*]}"
        return 1
    fi
    
    log_success "Configuration validation passed"
    return 0
}

# Display configuration summary
show_configuration_summary() {
    log_header "Configuration Summary"
    
    echo -e "${BOLD}Services to be installed:${NC}"
    [[ $INSTALL_POSTGRES =~ ^[Yy]$ ]] && echo -e "  ${GREEN}✓${NC} PostgreSQL Database"
    [[ $INSTALL_PGADMIN =~ ^[Yy]$ ]] && echo -e "  ${GREEN}✓${NC} PgAdmin"
    [[ $INSTALL_RABBITMQ =~ ^[Yy]$ ]] && echo -e "  ${GREEN}✓${NC} RabbitMQ"
    [[ $INSTALL_REDIS =~ ^[Yy]$ ]] && echo -e "  ${GREEN}✓${NC} Redis"
    [[ $INSTALL_REDIS_INSIGHT =~ ^[Yy]$ ]] && echo -e "  ${GREEN}✓${NC} Redis Insight"
    [[ $INSTALL_MINIO =~ ^[Yy]$ ]] && echo -e "  ${GREEN}✓${NC} MinIO Object Storage"
    [[ $INSTALL_PORTAINER =~ ^[Yy]$ ]] && echo -e "  ${GREEN}✓${NC} Portainer"
    [[ $INSTALL_WEBAPP =~ ^[Yy]$ ]] && echo -e "  ${GREEN}✓${NC} Main Web Application"
    [[ $INSTALL_CLIENT =~ ^[Yy]$ ]] && echo -e "  ${GREEN}✓${NC} Client Application"
    [[ $INSTALL_PROCESSOR =~ ^[Yy]$ ]] && echo -e "  ${GREEN}✓${NC} Processor Service (${PROCESSOR_REPLICAS} replicas)"
    [[ $INSTALL_WORKER =~ ^[Yy]$ ]] && echo -e "  ${GREEN}✓${NC} Order Worker Service (${WORKER_REPLICAS} replicas)"
    [[ $INSTALL_JOBS =~ ^[Yy]$ ]] && echo -e "  ${GREEN}✓${NC} Jobs Service"
    [[ $INSTALL_CADDY =~ ^[Yy]$ ]] && echo -e "  ${GREEN}✓${NC} Caddy Reverse Proxy"
    
    echo -e "\n${BOLD}Domain Configuration:${NC}"
    echo -e "  Main Domain:      ${BLUE}${DOMAIN}${NC}"
    echo -e "  Client App:       ${BLUE}${CLIENT_APP_DOMAIN}${NC}"
    [[ $INSTALL_PGADMIN =~ ^[Yy]$ ]] && echo -e "  PgAdmin:          ${BLUE}${PGADMIN_DOMAIN}${NC}"
    [[ $INSTALL_PORTAINER =~ ^[Yy]$ ]] && echo -e "  Portainer:        ${BLUE}${PORTAINER_DOMAIN}${NC}"
    [[ $INSTALL_RABBITMQ =~ ^[Yy]$ ]] && echo -e "  RabbitMQ:         ${BLUE}${RABBITMQ_DOMAIN}${NC}"
    [[ $INSTALL_REDIS_INSIGHT =~ ^[Yy]$ ]] && echo -e "  Redis Insight:    ${BLUE}${REDISINSIGHT_DOMAIN}${NC}"
    [[ $INSTALL_MINIO =~ ^[Yy]$ ]] && echo -e "  MinIO Console:    ${BLUE}${MINIO_DOMAIN}${NC}"
    [[ $INSTALL_MINIO =~ ^[Yy]$ ]] && echo -e "  MinIO Files:      ${BLUE}${FILES_DOMAIN}${NC}"
    
    echo ""
}

# Deploy services
deploy_services() {
    log_header "Deploying Services"
    
    # Pull images
    log_info "Pulling Docker images..."
    docker compose pull
    
    # Create networks if they don't exist
    log_info "Creating Docker networks..."
    docker network create digitalbot_web 2>/dev/null || true
    docker network create digitalbot_internal 2>/dev/null || true
    
    # Start services
    log_info "Starting services..."
    docker compose up -d
    
    # Wait for services to be healthy
    log_info "Waiting for services to be healthy..."
    sleep 10
    
    log_success "Services deployed successfully"
}

# Show post-installation information
show_post_installation() {
    log_header "Installation Complete!"
    
    echo -e "${GREEN}${BOLD}Digital Bot Infrastructure has been successfully installed!${NC}\n"
    
    echo -e "${BOLD}Next Steps:${NC}"
    echo -e "1. Ensure DNS records are configured for all domains"
    echo -e "2. Wait for SSL certificates to be automatically provisioned"
    echo -e "3. Access your services at the configured domains\n"
    
    echo -e "${BOLD}Useful Commands:${NC}"
    echo -e "  Check service status:  ${BLUE}docker compose ps${NC}"
    echo -e "  View logs:             ${BLUE}docker compose logs -f [service_name]${NC}"
    echo -e "  Stop services:         ${BLUE}docker compose down${NC}"
    echo -e "  Restart services:      ${BLUE}docker compose restart${NC}"
    echo -e "  Update services:       ${BLUE}docker compose pull && docker compose up -d${NC}\n"
    
    if [ -d "$BACKUP_DIR" ]; then
        echo -e "${BOLD}Backup:${NC}"
        echo -e "  Previous configuration backed up to: ${BLUE}${BACKUP_DIR}${NC}\n"
    fi
    
    echo -e "${BOLD}Configuration Files:${NC}"
    echo -e "  Environment:           ${BLUE}${ENV_FILE}${NC}"
    echo -e "  Docker Compose:        ${BLUE}${SCRIPT_DIR}/docker-compose.yml${NC}"
    echo -e "  Caddyfile:             ${BLUE}${SCRIPT_DIR}/Caddyfile${NC}\n"
    
    echo -e "${YELLOW}Important:${NC} Keep your .env file secure as it contains sensitive information!\n"
}

# Main installation flow
main() {
    show_banner
    
    # Pre-installation checks
    check_root
    check_system_requirements
    check_install_docker
    check_docker_compose
    
    # Backup existing configuration
    backup_existing_config
    
    # Interactive configuration
    select_services
    collect_env_variables
    
    # Generate configuration files
    generate_env_file
    update_caddyfile
    
    # Validate configuration
    if ! validate_configuration; then
        log_error "Configuration validation failed"
        exit 1
    fi
    
    # Show summary and confirm
    show_configuration_summary
    
    echo -e "\n${YELLOW}${BOLD}Ready to deploy?${NC}"
    read -p "Continue with deployment? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        log_warning "Installation cancelled by user"
        exit 0
    fi
    
    # Deploy services
    deploy_services
    
    # Show post-installation information
    show_post_installation
}

# Run main function
main "$@"
