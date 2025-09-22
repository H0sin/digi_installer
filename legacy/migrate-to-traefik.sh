#!/bin/bash

# 🚀 Digital Bot - Migration Script: HAProxy to Traefik
# This script helps migrate from HAProxy to Traefik as the primary reverse proxy

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_FILE="docker-compose.yml"
ENV_FILE=".env"
BACKUP_DIR="./backup_$(date +%Y%m%d_%H%M%S)"

# Helper functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Ensure we're in the right directory
if [[ ! -f "$COMPOSE_FILE" ]] || [[ ! -f "$ENV_FILE" ]]; then
    log_error "docker-compose.yml or .env file not found. Please run this script from the project root."
    exit 1
fi

log_info "Starting migration from HAProxy to Traefik..."

# Create backup
log_info "Creating backup of current configuration..."
mkdir -p "$BACKUP_DIR"
cp "$COMPOSE_FILE" "$BACKUP_DIR/"
cp "$ENV_FILE" "$BACKUP_DIR/"
log_success "Backup created in $BACKUP_DIR"

# Check if HAProxy is currently running
if docker compose ps haproxy 2>/dev/null | grep -q "Up"; then
    log_warning "HAProxy is currently running. Stopping it..."
    docker compose stop haproxy
    log_success "HAProxy stopped"
fi

# Validate Traefik configuration
log_info "Validating Traefik configuration..."
if ! docker compose config --quiet; then
    log_error "Docker Compose configuration validation failed!"
    log_info "Restoring backup..."
    cp "$BACKUP_DIR/$COMPOSE_FILE" .
    cp "$BACKUP_DIR/$ENV_FILE" .
    exit 1
fi
log_success "Configuration validated"

# Check required environment variables
log_info "Checking required environment variables..."
source "$ENV_FILE"

required_vars=(
    "TRAEFIK_ACME_EMAIL"
    "DOMAIN"
    "CLIENT_APP_DOMAIN"
    "RABBITMQ_DOMAIN"
    "PGADMIN_DOMAIN"
    "PORTAINER_DOMAIN"
    "REDISINSIGHT_DOMAIN"
)

missing_vars=()
for var in "${required_vars[@]}"; do
    if [[ -z "${!var}" ]]; then
        missing_vars+=("$var")
    fi
done

if [[ ${#missing_vars[@]} -gt 0 ]]; then
    log_error "Missing required environment variables:"
    for var in "${missing_vars[@]}"; do
        echo "  - $var"
    done
    log_info "Please set these variables in $ENV_FILE"
    exit 1
fi
log_success "All required environment variables are set"

# Ensure traefik directory and dynamic config exist
log_info "Setting up Traefik configuration..."
mkdir -p traefik/dynamic
if [[ ! -f "traefik/dynamic/middlewares.yml" ]]; then
    log_warning "Traefik middlewares configuration not found - ensure it exists"
fi

# Create digitalbot_web network for services communication
log_info "Creating digitalbot_web network for services..."
if docker network create digitalbot_web 2>/dev/null; then
    log_success "digitalbot_web network created"
else
    log_info "digitalbot_web network already exists"
fi

log_success "Traefik configuration ready"

# Set proper permissions for ACME storage
log_info "Setting up SSL certificate storage..."
docker volume create "${COMPOSE_PROJECT_NAME}_traefik-letsencrypt" 2>/dev/null || true
log_success "SSL certificate storage ready"

# Start services
log_info "Starting services with Traefik..."
docker compose up -d

# Wait for services to be healthy
log_info "Waiting for services to become healthy..."
max_attempts=30
attempt=0

while [[ $attempt -lt $max_attempts ]]; do
    if docker compose ps | grep -q "unhealthy"; then
        sleep 10
        ((attempt++))
        log_info "Waiting... (attempt $attempt/$max_attempts)"
    else
        break
    fi
done

if [[ $attempt -eq $max_attempts ]]; then
    log_warning "Some services may not be fully healthy yet. Check with: docker compose ps"
else
    log_success "All services are running"
fi

# Display access URLs
log_success "🎉 Migration completed successfully!"
echo
log_info "Your services are now accessible at:"
echo "  📱 Main App:       https://$DOMAIN"
echo "  ⚛️  Client App:     https://$CLIENT_APP_DOMAIN"
echo "  🐰 RabbitMQ:       https://$RABBITMQ_DOMAIN"
echo "  🗄️  pgAdmin:        https://$PGADMIN_DOMAIN"
echo "  🐳 Portainer:      https://$PORTAINER_DOMAIN"
echo "  🔧 RedisInsight:   https://$REDISINSIGHT_DOMAIN"
if [[ -n "$TRAEFIK_DOMAIN" ]]; then
    echo "  🔄 Traefik:        https://$TRAEFIK_DOMAIN"
fi
echo

# Cleanup suggestions
log_info "Post-migration steps:"
echo "  1. Test all services to ensure they're working correctly"
echo "  2. Monitor SSL certificate issuance (may take a few minutes)"
echo "  3. For Cloudflare 521 errors, run: ./fix-521-error.sh"
echo "  4. Comprehensive diagnostics: ./troubleshoot-521.sh"
echo "  5. Update any external monitoring or scripts that referenced HAProxy"
echo "  6. Backup can be found in: $BACKUP_DIR"
echo

# Show useful commands
log_info "Useful commands:"
echo "  🔍 Check service status:    docker compose ps"
echo "  📋 View Traefik logs:       docker compose logs -f traefik"
echo "  🔄 Restart services:        docker compose restart"
echo "  🛑 Stop all services:       docker compose down"
echo "  🚨 Fix 521 errors:          ./fix-521-error.sh"
echo "  🔍 Troubleshoot issues:     ./troubleshoot-521.sh"
echo "  💾 Backup certificates:     docker cp traefik:/letsencrypt ./letsencrypt-backup"
echo

log_success "🚀 Traefik is now your primary reverse proxy!"