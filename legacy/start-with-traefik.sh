#!/bin/bash

# 🚀 Digital Bot - Optimized Start with Traefik
# Fast and efficient startup script for better SSL certificate performance

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

# Ensure we're in the right directory
if [[ ! -f "docker-compose.yml" ]] || [[ ! -f ".env" ]]; then
    log_error "docker-compose.yml or .env file not found. Please run this script from the project root."
    exit 1
fi

log_info "🚀 Starting Digital Bot with optimized Traefik configuration..."

# 1. Quick network and volume setup
log_info "Setting up networking..."
docker network create digitalbot_web 2>/dev/null || log_info "Network ready"

# 2. Ensure traefik directories exist
mkdir -p traefik/dynamic letsencrypt
touch letsencrypt/acme.json
chmod 600 letsencrypt/acme.json
docker volume create "${COMPOSE_PROJECT_NAME:-digitalbot}_traefik-letsencrypt" 2>/dev/null || true

# 3. Quick config validation
if ! docker compose config --quiet; then
    log_error "Docker Compose configuration has errors!"
    exit 1
fi

# 4. Start services efficiently (Traefik first for faster SSL)
log_info "Starting Traefik first (optimized for fast SSL certificates)..."
docker compose up -d traefik

log_info "Starting all services..."
docker compose up -d

# 5. Quick status check
log_success "🎉 Services started with optimized configuration!"
echo
source .env 2>/dev/null || true

log_info "Your services will be accessible at:"
[[ -n "$DOMAIN" ]] && echo "  📱 Main App:       https://$DOMAIN"
[[ -n "$CLIENT_APP_DOMAIN" ]] && echo "  ⚛️  Client App:     https://$CLIENT_APP_DOMAIN"
[[ -n "$TRAEFIK_DOMAIN" ]] && echo "  🔄 Traefik:        https://$TRAEFIK_DOMAIN"
[[ -n "$PGADMIN_DOMAIN" ]] && echo "  🗃️  pgAdmin:        https://$PGADMIN_DOMAIN"
[[ -n "$PORTAINER_DOMAIN" ]] && echo "  📊 Portainer:      https://$PORTAINER_DOMAIN"
echo

log_info "⚡ Key optimizations active:"
echo "  🚀 Traefik starts independently (no database wait)"
echo "  🔧 EC256 keys for faster certificate generation"
echo "  📈 Optimized TLS settings for Cloudflare compatibility"
echo "  ⏱️  Reduced DNS challenge delays"
echo

log_info "Monitor and troubleshoot:"
echo "  📋 Traefik logs:       docker compose logs -f traefik"
echo "  🔍 Service status:     docker compose ps"
echo "  🛠️  SSL troubleshoot:   ./fix-ssl-526.sh"
echo "  ✅ Test domain:        curl -I https://$DOMAIN"