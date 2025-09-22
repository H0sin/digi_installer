#!/bin/bash

# 🔧 Fix Cloudflare 521 Error Script
# This script addresses the specific issues causing 521 errors after HAProxy to Traefik migration

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

log_info "🔧 Starting Cloudflare 521 Error Fix..."

# 1. Stop any existing services
log_info "Stopping existing services..."
docker compose down 2>/dev/null || true

# 2. Clean up any existing port bindings
log_info "Cleaning up port conflicts..."
docker container prune -f 2>/dev/null || true

# 3. Check for port conflicts
log_info "Checking for port conflicts on 80 and 443..."
if netstat -tulpn 2>/dev/null | grep -q ":80 "; then
    log_warning "Port 80 is in use:"
    netstat -tulpn 2>/dev/null | grep ":80 " | head -3
    log_info "You may need to stop the conflicting service"
fi

if netstat -tulpn 2>/dev/null | grep -q ":443 "; then
    log_warning "Port 443 is in use:"
    netstat -tulpn 2>/dev/null | grep ":443 " | head -3
    log_info "You may need to stop the conflicting service"
fi

# 4. Ensure Traefik directories exist
log_info "Setting up Traefik configuration directories..."
mkdir -p traefik/dynamic
if [[ ! -f "traefik/dynamic/middlewares.yml" ]]; then
    log_warning "Traefik middlewares.yml not found - this may cause issues"
fi

# 5. Create SSL certificate storage
log_info "Setting up SSL certificate storage..."
docker volume create "${COMPOSE_PROJECT_NAME:-digitalbot}_traefik-letsencrypt" 2>/dev/null || true

# 6. Start core infrastructure first
log_info "Starting core infrastructure services..."
docker compose up -d postgres redis rabbitmq

# Wait for infrastructure to be healthy
log_info "Waiting for infrastructure services to be healthy..."
max_attempts=30
attempt=0

while [[ $attempt -lt $max_attempts ]]; do
    if docker compose ps postgres redis rabbitmq | grep -q "unhealthy"; then
        sleep 5
        ((attempt++))
        log_info "Waiting for infrastructure... (attempt $attempt/$max_attempts)"
    else
        break
    fi
done

if [[ $attempt -eq $max_attempts ]]; then
    log_warning "Infrastructure services may not be fully healthy yet"
else
    log_success "Infrastructure services are healthy"
fi

# 7. Start Traefik (the critical component for fixing 521 errors)
log_info "Starting Traefik reverse proxy..."
docker compose up -d traefik

# Wait for Traefik to start and bind to ports
log_info "Waiting for Traefik to bind to ports 80 and 443..."
sleep 10

# Check if Traefik is working
if docker compose ps traefik | grep -q "Up"; then
    log_success "Traefik container is running"
    
    # Check if ports are now listening
    if netstat -tulpn 2>/dev/null | grep -q ":80.*LISTEN"; then
        log_success "Port 80 is now listening"
    else
        log_error "Port 80 is still not listening"
    fi
    
    if netstat -tulpn 2>/dev/null | grep -q ":443.*LISTEN"; then
        log_success "Port 443 is now listening"
    else
        log_error "Port 443 is still not listening"
    fi
    
    # Test Traefik API
    if curl -s http://localhost:8080/ping >/dev/null 2>&1; then
        log_success "Traefik API is responding"
    else
        log_warning "Traefik API is not responding yet (this is normal during startup)"
    fi
else
    log_error "Traefik failed to start"
    log_info "Checking Traefik logs..."
    docker compose logs traefik | tail -20
    exit 1
fi

# 8. Start remaining services
log_info "Starting remaining services..."
docker compose up -d

# 9. Wait for all services to be ready
log_info "Waiting for all services to be ready..."
sleep 20

# 10. Show final status
log_info "Final service status:"
docker compose ps

# 11. Show listening ports
log_info "Services listening on ports 80 and 443:"
netstat -tulpn 2>/dev/null | grep -E ":80|:443" || log_warning "No services found listening on ports 80/443"

# 12. Display access information
source .env 2>/dev/null || true

log_success "🎉 Fix attempt completed!"
echo
log_info "Your services should now be accessible at:"
if [[ -n "$DOMAIN" ]]; then
    echo "  📱 Main App:       https://$DOMAIN"
fi
if [[ -n "$CLIENT_APP_DOMAIN" ]]; then
    echo "  ⚛️  Client App:     https://$CLIENT_APP_DOMAIN"
fi
if [[ -n "$TRAEFIK_DOMAIN" ]]; then
    echo "  🔄 Traefik:        https://$TRAEFIK_DOMAIN"
fi
echo

log_info "Important notes for Cloudflare users:"
echo "  1. If using HTTP-01 challenge, temporarily set DNS to 'DNS-only' (gray cloud)"
echo "  2. Wait for SSL certificates to be issued (check: docker compose logs traefik)"
echo "  3. Once certificates are issued, you can re-enable 'Proxied' (orange cloud)"
echo "  4. For wildcard certificates, use DNS-01 challenge with CLOUDFLARE_API_TOKEN"
echo

log_info "If you still see 521 errors:"
echo "  1. Run: ./troubleshoot-521.sh"
echo "  2. Check Traefik logs: docker compose logs traefik"
echo "  3. Verify DNS records point to your server IP"
echo "  4. Ensure firewall allows ports 80 and 443"