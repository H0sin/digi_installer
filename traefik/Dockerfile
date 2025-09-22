FROM traefik:v3.0

# Copy template and entrypoint script
COPY dynamic.tmpl.yml /etc/traefik/dynamic.tmpl.yml
COPY entrypoint.sh /entrypoint.sh

# Make entrypoint executable
RUN chmod +x /entrypoint.sh

# Use custom entrypoint
ENTRYPOINT ["/entrypoint.sh"]