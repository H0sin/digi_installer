#!/bin/bash

# 🚀 Digi Installer
# Simple installation script for Digi service

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

# Banner
echo -e "${GREEN}"
echo "  ██████  ██  ██████  ██     "
echo "  ██   ██ ██ ██       ██     "
echo "  ██   ██ ██ ██   ███ ██     "
echo "  ██   ██ ██ ██    ██ ██     "
echo "  ██████  ██  ██████  ██     "
echo ""
echo "  🚀 Digi Installer v1.0"
echo -e "${NC}"

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   log_error "This script should not be run as root for security reasons."
   exit 1
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed. Please install Docker first."
    log_info "You can install Docker using: curl -fsSL https://get.docker.com | sh"
    exit 1
fi

# Check if Docker Compose is available
if ! docker compose version &> /dev/null; then
    log_error "Docker Compose is not available. Please install Docker Compose."
    exit 1
fi

# Create .env file if it doesn't exist
if [[ ! -f .env ]]; then
    log_info "Creating environment configuration..."
    cp .env.example .env
    log_warning "Please edit .env file with your configuration before continuing."
    log_info "Minimum required: Set your domain name and passwords"
    echo ""
    read -p "Press Enter to continue after editing .env file..."
fi

# Load environment variables
source .env

# Validate required variables
if [[ -z "$DOMAIN" || "$DOMAIN" == "yourdomain.com" ]]; then
    log_error "Please set your DOMAIN in .env file"
    exit 1
fi

# Create necessary directories
log_info "Creating directories..."
mkdir -p data/postgres
mkdir -p data/redis
mkdir -p logs
mkdir -p ssl

# Generate SSL certificate if not exists
log_info "Setting up SSL certificate..."
./generate-ssl.sh

# Create docker network
log_info "Creating Docker network..."
docker network create digi_network 2>/dev/null || log_info "Network already exists"

# Pull images
log_info "Pulling Docker images..."
docker compose pull

# Start services
log_info "Starting Digi services..."
docker compose up -d

# Wait for services to be ready
log_info "Waiting for services to start..."
sleep 10

# Check service status
if docker compose ps | grep -q "Up"; then
    log_success "🎉 Digi installation completed successfully!"
    echo ""
    log_info "Your Digi service is accessible at:"
    echo "  🌐 Main App: https://$DOMAIN"
    echo ""
    log_info "Useful commands:"
    echo "  📋 Check status: docker compose ps"
    echo "  📄 View logs: docker compose logs -f"
    echo "  🔄 Restart: docker compose restart"
    echo "  🛑 Stop: docker compose down"
else
    log_error "Some services failed to start. Check logs with: docker compose logs"
    exit 1
fi