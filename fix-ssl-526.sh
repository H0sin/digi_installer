#!/bin/bash

# 🔧 SSL Certificate Fix for Cloudflare Error 526 (Optimized)
# This script provides a fast and efficient solution for SSL validation issues

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

log_header "Fast SSL Certificate Fix for Cloudflare Error 526"

# 1. Load environment and validate
log_info "Loading environment configuration..."
source .env 2>/dev/null || { log_error "Could not load .env file"; exit 1; }

# 2. Verify required variables
if [[ -z "$TRAEFIK_ACME_EMAIL" ]]; then
    log_error "TRAEFIK_ACME_EMAIL is not set in .env file"
    log_info "Please set a valid email address for Let's Encrypt certificate registration"
    exit 1
fi

if [[ -z "$DOMAIN" ]]; then
    log_error "DOMAIN is not set in .env file"
    exit 1
fi

log_success "Email: $TRAEFIK_ACME_EMAIL | Domain: $DOMAIN"

# 3. Quick Cloudflare setup reminder
log_header "Cloudflare Setup Reminder"
log_info "Ensure your Cloudflare settings are:"
echo "  🔒 SSL/TLS mode: 'Full' (recommended) or 'Full (strict)'"
echo "  🌐 DNS: Can be 'Proxied' (orange cloud) - the new config handles this better"
echo "  ⚡ This optimized setup works faster with Cloudflare proxy enabled"

# 4. Quick cleanup and setup
log_info "Preparing optimized environment..."
docker compose down --remove-orphans 2>/dev/null || true

# Create network and volumes efficiently
docker network create digitalbot_web 2>/dev/null || log_info "Network ready"
docker volume create "${COMPOSE_PROJECT_NAME:-digitalbot}_traefik-letsencrypt" 2>/dev/null || true

# 5. Start Traefik first (optimized - no dependencies)
log_info "Starting Traefik with optimized SSL configuration..."
docker compose up -d traefik

# 6. Quick health check for Traefik
log_info "Checking Traefik readiness..."
for i in {1..10}; do
    if curl -s http://localhost:8080/ping >/dev/null 2>&1; then
        log_success "Traefik is ready!"
        break
    fi
    if [[ $i -eq 10 ]]; then
        log_warning "Traefik taking longer than expected, but continuing..."
        break
    fi
    sleep 2
done

# 7. Start remaining services
log_info "Starting all services..."
docker compose up -d

# 8. Quick status check
log_info "Final service status:"
docker compose ps --format "table {{.Service}}\t{{.State}}\t{{.Status}}"

log_header "🎉 Optimized SSL Setup Complete!"
log_success "Traefik is now configured with optimized settings for Cloudflare compatibility"
echo
log_info "Key improvements:"
echo "  ⚡ Faster certificate acquisition (EC256 keys, reduced delays)"
echo "  🔧 Optimized TLS configuration for Cloudflare"
echo "  🚀 Traefik starts independently (no database dependencies)"
echo "  📈 Better performance with HTTP/2 and modern ciphers"
echo
log_info "Monitor certificate issuance:"
echo "  📋 Traefik logs: docker compose logs -f traefik"
echo "  🔍 ACME logs: docker compose logs traefik | grep -i acme"
echo "  ✅ Test domain: curl -I https://$DOMAIN"
echo
log_success "🚀 Your SSL certificates should be acquired much faster now!"