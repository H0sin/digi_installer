#!/bin/bash

# Digital Bot Infrastructure Setup Script
# This script prepares the environment for running the application

set -e

echo "🚀 Setting up Digital Bot Infrastructure..."

# Create required Docker networks
echo "📡 Creating Docker networks..."

# Create external web network (for Traefik and web-facing services)
if ! docker network inspect digitalbot_web >/dev/null 2>&1; then
    docker network create digitalbot_web
    echo "✅ Created digitalbot_web network"
else
    echo "✅ digitalbot_web network already exists"
fi

# Internal network will be created automatically by docker-compose

echo "🔧 Generating authentication hashes..."

# Check if htpasswd is available for generating bcrypt hashes
if command -v htpasswd >/dev/null 2>&1; then
    echo "📝 htpasswd is available for generating secure auth hashes"
else
    echo "⚠️  htpasswd not found. Please install apache2-utils package for secure auth:"
    echo "    sudo apt-get install apache2-utils"
    echo "    Or manually generate bcrypt hashes for TRAEFIK_DASHBOARD_AUTH and TRAEFIK_ADMIN_AUTH"
fi

echo "🔍 Environment check:"
if [ -f .env ]; then
    echo "✅ .env file found"
    # Check for required environment variables
    required_vars=("DOMAIN" "TRAEFIK_DOMAIN" "PGADMIN_DOMAIN" "PORTAINER_DOMAIN" "RABBITMQ_DOMAIN" "CLIENT_APP_DOMAIN" "REDISINSIGHT_DOMAIN")
    
    for var in "${required_vars[@]}"; do
        if grep -q "^${var}=" .env; then
            echo "✅ ${var} is configured"
        else
            echo "❌ ${var} is missing in .env"
        fi
    done
else
    echo "❌ .env file not found"
    exit 1
fi

echo ""
echo "🎯 Setup complete! You can now run:"
echo "   docker compose up -d"
echo ""
echo "📋 Your configured domains:"
echo "   Main App: $(grep "^DOMAIN=" .env | cut -d'=' -f2)"
echo "   Traefik:  $(grep "^TRAEFIK_DOMAIN=" .env | cut -d'=' -f2)"
echo "   PgAdmin:  $(grep "^PGADMIN_DOMAIN=" .env | cut -d'=' -f2)"
echo "   Portainer: $(grep "^PORTAINER_DOMAIN=" .env | cut -d'=' -f2)"
echo "   RabbitMQ: $(grep "^RABBITMQ_DOMAIN=" .env | cut -d'=' -f2)"
echo "   Client:   $(grep "^CLIENT_APP_DOMAIN=" .env | cut -d'=' -f2)"
echo "   Redis:    $(grep "^REDISINSIGHT_DOMAIN=" .env | cut -d'=' -f2)"