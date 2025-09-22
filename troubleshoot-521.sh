#!/bin/bash

# 🔍 Cloudflare 521 Error Troubleshooting Script
# This script helps diagnose "Web server is down" errors after Traefik migration

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
    echo -e "${BLUE}🔍 $1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Check if we're in the right directory
if [[ ! -f "docker-compose.yml" ]] || [[ ! -f ".env" ]]; then
    log_error "docker-compose.yml or .env file not found. Please run this script from the project root."
    exit 1
fi

log_header "Cloudflare 521 Error Diagnostic"

# 1. Check if ports 80 and 443 are listening
log_header "1. Port Availability Check"
log_info "Checking if services are listening on ports 80 and 443..."

if netstat -tulpn 2>/dev/null | grep -q ":80 "; then
    log_success "Port 80 is listening"
    netstat -tulpn 2>/dev/null | grep ":80 " | head -3
else
    log_error "Port 80 is NOT listening - this will cause Cloudflare 521 error"
fi

if netstat -tulpn 2>/dev/null | grep -q ":443 "; then
    log_success "Port 443 is listening"
    netstat -tulpn 2>/dev/null | grep ":443 " | head -3
else
    log_error "Port 443 is NOT listening - this will cause Cloudflare 521 error"
fi

# 2. Check Docker services status
log_header "2. Docker Services Status"
log_info "Checking Docker Compose services status..."

if docker compose ps 2>/dev/null | grep -q "Up"; then
    log_info "Docker services status:"
    docker compose ps
else
    log_error "No Docker services are running!"
    log_info "Try starting services with: docker compose up -d"
fi

# 3. Check Traefik specifically
log_header "3. Traefik Service Check"
if docker compose ps traefik 2>/dev/null | grep -q "Up"; then
    log_success "Traefik container is running"
    
    # Check Traefik logs for errors
    log_info "Recent Traefik logs (last 20 lines):"
    docker compose logs --tail=20 traefik 2>/dev/null || log_warning "Could not retrieve Traefik logs"
    
    # Check if Traefik API is accessible
    if curl -s http://localhost:8080/ping >/dev/null 2>&1; then
        log_success "Traefik API is responding"
    else
        log_warning "Traefik API is not responding on port 8080"
    fi
else
    log_error "Traefik container is NOT running!"
    log_info "This is likely the cause of the 521 error"
fi

# 4. Check environment variables
log_header "4. Environment Configuration Check"
source .env 2>/dev/null || log_warning "Could not source .env file"

if [[ -n "$TRAEFIK_ACME_EMAIL" ]]; then
    log_success "TRAEFIK_ACME_EMAIL is set: $TRAEFIK_ACME_EMAIL"
else
    log_error "TRAEFIK_ACME_EMAIL is not set - SSL certificates won't work"
fi

if [[ -n "$DOMAIN" ]]; then
    log_success "DOMAIN is set: $DOMAIN"
else
    log_error "DOMAIN is not set"
fi

# 5. Check DNS resolution
log_header "5. DNS Resolution Check"
if [[ -n "$DOMAIN" ]]; then
    log_info "Checking DNS resolution for $DOMAIN..."
    if nslookup "$DOMAIN" >/dev/null 2>&1; then
        nslookup "$DOMAIN" | grep -A 2 "Non-authoritative answer:" || true
    else
        log_warning "DNS resolution failed for $DOMAIN"
    fi
else
    log_warning "Skipping DNS check - DOMAIN not set"
fi

# 6. Check UFW firewall status
log_header "6. Firewall Check"
if command -v ufw >/dev/null 2>&1; then
    UFW_STATUS=$(ufw status 2>/dev/null | head -1)
    if echo "$UFW_STATUS" | grep -q "Status: active"; then
        log_warning "UFW firewall is active"
        log_info "Checking if ports 80 and 443 are allowed..."
        
        if ufw status | grep -q "80/tcp"; then
            log_success "Port 80 is allowed through UFW"
        else
            log_error "Port 80 is NOT allowed through UFW"
            log_info "Run: sudo ufw allow 80/tcp"
        fi
        
        if ufw status | grep -q "443/tcp"; then
            log_success "Port 443 is allowed through UFW"
        else
            log_error "Port 443 is NOT allowed through UFW"
            log_info "Run: sudo ufw allow 443/tcp"
        fi
    else
        log_info "UFW firewall is inactive"
    fi
else
    log_info "UFW is not installed"
fi

# 7. Check for crashed containers
log_header "7. Container Crash Check"
log_info "Checking for crashed containers (Exit codes)..."

CRASHED_CONTAINERS=$(docker compose ps -a 2>/dev/null | grep "Exit" || true)
if [[ -n "$CRASHED_CONTAINERS" ]]; then
    log_error "Found crashed containers:"
    echo "$CRASHED_CONTAINERS"
    
    # Check for Exit 139 specifically (SIGSEGV)
    if echo "$CRASHED_CONTAINERS" | grep -q "Exit 139"; then
        log_error "Exit 139 detected - this indicates segmentation fault (SIGSEGV)"
        log_info "This could be caused by:"
        echo "  - Memory issues (insufficient RAM)"
        echo "  - Incompatible architecture (ARM vs x86)"
        echo "  - Corrupted image or dependencies"
        echo "  - Resource limits being exceeded"
    fi
else
    log_success "No crashed containers found"
fi

# 8. Recommendations
log_header "8. Recommendations"

echo "If you're experiencing Cloudflare 521 errors, try these steps in order:"
echo
echo "1. 🚀 Start Traefik and basic services:"
echo "   docker compose up -d traefik postgres rabbitmq redis"
echo
echo "2. ⏳ Wait for infrastructure to be healthy, then start web services:"
echo "   docker compose up -d"
echo
echo "3. 🔍 Check service health:"
echo "   docker compose ps"
echo "   docker compose logs traefik"
echo
echo "4. 🌐 Test connectivity:"
echo "   curl -I http://localhost"
echo "   curl -I https://localhost"
echo
echo "5. 📋 For Cloudflare setup with HTTP-01 challenge:"
echo "   - Temporarily set DNS records to 'DNS-only' (gray cloud)"
echo "   - Wait for SSL certificate issuance"
echo "   - Re-enable 'Proxied' (orange cloud) after certificates are issued"
echo
echo "6. 🔐 For wildcard certificates (DNS-01 challenge):"
echo "   - Set TRAEFIK_CERT_RESOLVER=dnsresolver in .env"
echo "   - Ensure CLOUDFLARE_API_TOKEN is properly set"
echo "   - Verify API token has Zone:DNS:Edit permissions"
echo

log_success "Diagnostic complete! Check the output above for issues."