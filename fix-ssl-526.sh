#!/bin/bash

# 🔧 SSL Certificate Fix for Cloudflare Error 526
# This script addresses SSL validation issues between Cloudflare and Traefik

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

log_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}🔧 $1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Check if we're in the right directory
if [[ ! -f "docker-compose.yml" ]] || [[ ! -f ".env" ]]; then
    log_error "docker-compose.yml or .env file not found. Please run this script from the project root."
    exit 1
fi

log_header "Cloudflare SSL Error 526 Fix"

# 1. Check current environment
log_info "Loading environment configuration..."
source .env 2>/dev/null || log_error "Could not load .env file"

# 2. Verify required variables
log_info "Checking SSL configuration..."
if [[ -z "$TRAEFIK_ACME_EMAIL" ]]; then
    log_error "TRAEFIK_ACME_EMAIL is not set in .env file"
    log_info "Please set a valid email address for Let's Encrypt certificate registration"
    exit 1
fi

if [[ -z "$DOMAIN" ]]; then
    log_error "DOMAIN is not set in .env file"
    exit 1
fi

log_success "TRAEFIK_ACME_EMAIL: $TRAEFIK_ACME_EMAIL"
log_success "DOMAIN: $DOMAIN"

# 3. Check Cloudflare SSL mode recommendations
log_header "Cloudflare SSL Configuration Check"
log_info "For Error 526 fixes, ensure your Cloudflare SSL/TLS settings are:"
echo "  1. 🔒 SSL/TLS mode: 'Full' or 'Full (strict)'"
echo "  2. 🌐 Temporarily set DNS to 'DNS-only' (gray cloud) during certificate issuance"
echo "  3. ⏰ Wait for Let's Encrypt certificate to be issued"
echo "  4. 🔄 Re-enable 'Proxied' (orange cloud) after successful certificate validation"

# 4. Stop any running services
log_info "Stopping existing services..."
docker compose down --remove-orphans 2>/dev/null || true

# 5. Ensure networks and volumes exist
log_info "Setting up Docker networks and volumes..."
docker network create digitalbot_web 2>/dev/null || log_info "digitalbot_web network already exists"
docker volume create "${COMPOSE_PROJECT_NAME:-digitalbot}_traefik-letsencrypt" 2>/dev/null || true

# 6. Start infrastructure services first
log_info "Starting infrastructure services..."
docker compose up -d postgres redis rabbitmq

# Wait for infrastructure
log_info "Waiting for infrastructure services to be healthy..."
max_attempts=30
attempt=0
while [[ $attempt -lt $max_attempts ]]; do
    if docker compose ps postgres | grep -q "healthy" && \
       docker compose ps redis | grep -q "healthy" && \
       docker compose ps rabbitmq | grep -q "healthy"; then
        log_success "Infrastructure services are healthy"
        break
    fi
    attempt=$((attempt + 1))
    echo "Waiting for services... ($attempt/$max_attempts)"
    sleep 5
done

if [[ $attempt -eq $max_attempts ]]; then
    log_error "Infrastructure services failed to become healthy"
    docker compose logs postgres redis rabbitmq | tail -50
    exit 1
fi

# 7. Start Traefik with new configuration
log_info "Starting Traefik with SSL fix..."
docker compose up -d traefik

# Wait for Traefik to be ready
log_info "Waiting for Traefik to be ready..."
max_attempts=20
attempt=0
while [[ $attempt -lt $max_attempts ]]; do
    if curl -s http://localhost:8080/ping >/dev/null 2>&1; then
        log_success "Traefik ping endpoint is responding"
        break
    fi
    attempt=$((attempt + 1))
    echo "Waiting for Traefik... ($attempt/$max_attempts)"
    sleep 3
done

if [[ $attempt -eq $max_attempts ]]; then
    log_error "Traefik failed to start properly"
    log_info "Checking Traefik logs..."
    docker compose logs traefik | tail -20
    exit 1
fi

# 8. Start remaining services
log_info "Starting remaining services..."
docker compose up -d

# 9. Final health check
log_info "Performing final health checks..."
sleep 10

# Check ports
if netstat -tulpn 2>/dev/null | grep -q ":80.*LISTEN"; then
    log_success "Port 80 is listening"
else
    log_warning "Port 80 is not listening yet"
fi

if netstat -tulpn 2>/dev/null | grep -q ":443.*LISTEN"; then
    log_success "Port 443 is listening"
else
    log_warning "Port 443 is not listening yet"
fi

# 10. Show final status
log_header "Service Status"
docker compose ps

log_header "SSL Certificate Fix Complete"
log_success "Traefik has been configured with SSL fixes for Cloudflare compatibility"
echo
log_info "Next steps:"
echo "  1. 🌐 Monitor certificate issuance: docker compose logs traefik | grep -i acme"
echo "  2. 🔄 Wait 1-2 minutes for Let's Encrypt certificate validation"
echo "  3. ✅ Test your domain: curl -I https://$DOMAIN"
echo "  4. 🔒 Re-enable Cloudflare proxy (orange cloud) after certificates are issued"
echo
log_info "If you still see Error 526:"
echo "  1. Check Cloudflare SSL/TLS mode is set to 'Full'"
echo "  2. Verify your domain DNS points to this server"
echo "  3. Run: ./troubleshoot-521.sh"
echo "  4. Check logs: docker compose logs traefik"

log_success "SSL fix deployment completed!"