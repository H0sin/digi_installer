FROM traefik:v3.0

# Install gettext-base package for envsubst command
RUN apk add --no-cache gettext-base

# Copy template and entrypoint script
COPY dynamic.tmpl.yml /etc/traefik/dynamic.tmpl.yml
COPY entrypoint.sh /entrypoint.sh

# Make entrypoint executable
RUN chmod +x /entrypoint.sh

# Use custom entrypoint
ENTRYPOINT ["/entrypoint.sh"]