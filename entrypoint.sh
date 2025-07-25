#!/bin/sh
set -e

# Substitute environment variables in the template file
envsubst '$DOMAIN,$RABBITMQ_DOMAIN,$PGADMIN_DOMAIN,$PORTAINER_DOMAIN,$CLIENT_APP_DOMAIN,$HAPROXY_STATS_PASS' < /usr/local/etc/haproxy/haproxy.cfg.template > /usr/local/etc/haproxy/haproxy.cfg

# Optional: Display the generated config for debugging
echo "--- Generated haproxy.cfg ---"
cat /usr/local/etc/haproxy/haproxy.cfg
echo "-----------------------------"

# Execute the original command of the container
exec "$@"