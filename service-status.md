# Service Status Summary

## Successfully Running Services:
NAME           IMAGE                           COMMAND                  SERVICE        CREATED              STATUS                                 PORTS
pgadmin        dpage/pgadmin4                  "/entrypoint.sh"         pgadmin        About a minute ago   Up About a minute (healthy)            80/tcp, 443/tcp
portainer      portainer/portainer-ce:latest   "/portainer -H unix:…"   portainer      About a minute ago   Up About a minute (health: starting)   8000/tcp, 9000/tcp, 9443/tcp
postgres       postgres:16-alpine              "docker-entrypoint.s…"   postgres       3 minutes ago        Up 3 minutes (healthy)                 0.0.0.0:5432->5432/tcp, [::]:5432->5432/tcp
rabbitmq       rabbitmq:3-management           "docker-entrypoint.s…"   rabbitmq       About a minute ago   Up 54 seconds (healthy)                4369/tcp, 5671-5672/tcp, 15671-15672/tcp, 15691-15692/tcp, 25672/tcp
redis          redis:7-alpine                  "docker-entrypoint.s…"   redis          3 minutes ago        Up 3 minutes (healthy)                 
redisinsight   redis/redisinsight:latest       "./docker-entry.sh n…"   redisinsight   About a minute ago   Up About a minute                      5540/tcp
traefik        digitalbot-traefik              "/entrypoint.sh --ap…"   traefik        2 minutes ago        Up 2 minutes (healthy)                 0.0.0.0:80->80/tcp, [::]:80->80/tcp, 0.0.0.0:443->443/tcp, [::]:443->443/tcp, 0.0.0.0:8080->8080/tcp, [::]:8080->8080/tcp

## Domain Configuration:
- Main App: be-unavailable.com
- Traefik Dashboard: traefik.be-unavailable.com
- PgAdmin: pgadmin.be-unavailable.com
- Portainer: portainer.be-unavailable.com
- RabbitMQ: rabbitmq.be-unavailable.com
- Client App: client.be-unavailable.com
- Redis Insight: redis-insight.be-unavailable.com
