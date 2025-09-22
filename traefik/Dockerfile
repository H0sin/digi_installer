FROM traefik:v3.0

# Remove the need for additional packages - using shell built-ins
# RUN apk add --no-cache gettext-tiny

# Copy template and entrypoint script
COPY dynamic.tmpl.yml /etc/traefik/dynamic.tmpl.yml
COPY entrypoint.sh /entrypoint.sh

# Make entrypoint executable
RUN chmod +x /entrypoint.sh

# Use custom entrypoint
ENTRYPOINT ["/entrypoint.sh"]