#!/bin/sh

# Traefik Custom Entrypoint Script
# This script processes configuration templates and starts Traefik

set -e

echo "🚀 Starting Custom Traefik with Dynamic Configuration..."

# Create dynamic configuration directory if it doesn't exist
mkdir -p /etc/traefik/dynamic

# Copy the template as the dynamic configuration
echo "📝 Processing dynamic configuration template..."
# Use shell-based substitution instead of envsubst (avoids dependency issues)
# Read the template file and substitute environment variables
while IFS= read -r line; do
    # Process each line for environment variable substitution
    echo "$line" | sed -e "s/\${TRAEFIK_ADMIN_AUTH}/${TRAEFIK_ADMIN_AUTH:-}/g" \
                      -e "s/\${TRAEFIK_DASHBOARD_AUTH}/${TRAEFIK_DASHBOARD_AUTH:-}/g"
done < /etc/traefik/dynamic.tmpl.yml > /etc/traefik/dynamic/dynamic.yml

echo "✅ Dynamic configuration processed successfully"

# Create Let's Encrypt directory and file if they don't exist
mkdir -p /letsencrypt
touch /letsencrypt/acme.json
chmod 600 /letsencrypt/acme.json

echo "🔒 SSL certificate storage prepared"

# Log configuration for debugging
echo "🔍 Configuration summary:"
echo "  - Dynamic config: /etc/traefik/dynamic/dynamic.yml"
echo "  - ACME storage: /letsencrypt/acme.json"
echo "  - Provider: ${ACME_DNS_PROVIDER:-cloudflare} (for DNS challenge)"
echo "  - Email: ${TRAEFIK_ACME_EMAIL:-not-set}"

# Start Traefik with all arguments passed to this script
echo "🌐 Starting Traefik..."
exec traefik "$@"