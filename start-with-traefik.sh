#!/bin/bash

# 🚀 Digital Bot - Start with Traefik
# This script ensures proper network setup and starts services with Traefik

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

log_info "🌐 Setting up Traefik network and configuration..."

# 1. Create web network for services communication
log_info "Creating web network for services..."
if docker network create web 2>/dev/null; then
    log_success "Web network created"
else
    log_info "Web network already exists"
fi

# 2. Ensure traefik directory and dynamic config exist
log_info "Setting up Traefik configuration directories..."
mkdir -p traefik/dynamic

# 3. Verify middleware configuration exists
if [[ ! -f "traefik/dynamic/middlewares.yml" ]]; then
    log_error "Traefik middlewares.yml not found!"
    exit 1
else
    log_success "Traefik middleware configuration found"
fi

# 4. Create SSL certificate storage
log_info "Setting up SSL certificate storage..."
mkdir -p letsencrypt
touch letsencrypt/acme.json
chmod 600 letsencrypt/acme.json
docker volume create "${COMPOSE_PROJECT_NAME:-digitalbot}_traefik-letsencrypt" 2>/dev/null || true
log_success "SSL certificate storage ready"

# 5. Validate docker-compose configuration
log_info "Validating Docker Compose configuration..."
if docker compose config --quiet; then
    log_success "Docker Compose configuration is valid"
else
    log_error "Docker Compose configuration has errors!"
    exit 1
fi

# 6. Start services
log_info "Starting services with Traefik..."
log_info "Starting infrastructure services first..."
docker compose up -d postgres redis rabbitmq

log_info "Starting Traefik reverse proxy..."
docker compose up -d traefik

log_info "Starting web applications..."
docker compose up -d

# 7. Show status
log_info "Checking service status..."
docker compose ps

log_success "🎉 Services started successfully!"
echo
log_info "Your services should be accessible at:"
source .env 2>/dev/null || true

if [[ -n "$DOMAIN" ]]; then
    echo "  📱 Main App:       https://$DOMAIN"
fi
if [[ -n "$CLIENT_APP_DOMAIN" ]]; then
    echo "  ⚛️  Client App:     https://$CLIENT_APP_DOMAIN"
fi
if [[ -n "$TRAEFIK_DOMAIN" ]]; then
    echo "  🔄 Traefik:        https://$TRAEFIK_DOMAIN"
fi
if [[ -n "$PGADMIN_DOMAIN" ]]; then
    echo "  🗃️  pgAdmin:        https://$PGADMIN_DOMAIN"
fi
if [[ -n "$PORTAINER_DOMAIN" ]]; then
    echo "  📊 Portainer:      https://$PORTAINER_DOMAIN"
fi
echo

log_info "Useful commands:"
echo "  🔍 Check service status:    docker compose ps"
echo "  📋 View Traefik logs:       docker compose logs -f traefik"
echo "  🛑 Stop all services:       docker compose down"
echo "  🚨 Fix 521 errors:          ./fix-521-error.sh"
echo "  🔍 Troubleshoot issues:     ./troubleshoot-521.sh"