# Installation Scenarios and Examples

This document provides examples for common installation scenarios.

## Table of Contents
- [Full Stack Installation](#full-stack-installation)
- [Database Server Only](#database-server-only)
- [Application Server Only](#application-server-only)
- [Development Environment](#development-environment)
- [Production Environment](#production-environment)
- [Distributed Setup](#distributed-setup)

---

## Full Stack Installation

Install all services on a single server.

### When to use:
- Small to medium-sized deployments
- Development/staging environments
- Simple production setups

### Installation Steps:
1. Run the installation script:
   ```bash
   ./install.sh
   ```

2. Answer "Y" (Yes) to all service prompts:
   - PostgreSQL database
   - PgAdmin
   - RabbitMQ
   - Redis
   - Redis Insight
   - MinIO
   - Portainer
   - Main web application
   - Client application
   - Processor service
   - Order worker service
   - Jobs service
   - Caddy reverse proxy

3. Provide your domain and configuration values

4. Wait for deployment to complete

### Result:
All services running on one server with proper networking and SSL certificates.

---

## Database Server Only

Install only database and related services.

### When to use:
- Dedicated database server in distributed setup
- Database management and monitoring

### Installation Steps:
1. Run the installation script:
   ```bash
   ./install.sh
   ```

2. Answer "Y" only to:
   - PostgreSQL database
   - PgAdmin
   - Portainer (optional, for management)

3. Answer "N" to all other services

### Configuration Notes:
- Make sure PostgreSQL port (5432) is accessible from application servers
- Configure firewall rules appropriately
- Use strong passwords
- Consider exposing only necessary ports

---

## Application Server Only

Install application services without databases.

### When to use:
- Horizontal scaling with separate database server
- Multiple application servers behind load balancer

### Installation Steps:
1. Run the installation script:
   ```bash
   ./install.sh
   ```

2. Answer "N" to:
   - PostgreSQL database
   - PgAdmin
   - RabbitMQ (if using external)
   - Redis (if using external)
   - Redis Insight
   - MinIO (if using external)

3. Answer "Y" to:
   - Main web application
   - Client application
   - Processor service (configure replicas based on load)
   - Order worker service (configure replicas based on load)
   - Jobs service
   - Caddy reverse proxy

4. When providing database credentials, use external database server details

### Configuration Notes:
- Ensure network connectivity to external services
- Use internal IP addresses or hostnames for database connections
- Configure proper DNS for load balancing

---

## Development Environment

Optimized setup for development.

### Recommendations:
- Install all services locally
- Use lower replica counts:
  - Processor replicas: 1-2
  - Worker replicas: 1
- Use `.local` or `.test` domains
- Enable all management UIs (PgAdmin, Redis Insight, RabbitMQ Management, Portainer)

### Installation:
```bash
./install.sh
```

Answer "Y" to all services and use low replica counts.

### Additional Setup:
```bash
# Add local domain to /etc/hosts for testing
echo "127.0.0.1 myapp.local" | sudo tee -a /etc/hosts
echo "127.0.0.1 client.myapp.local" | sudo tee -a /etc/hosts
```

---

## Production Environment

Optimized setup for production deployment.

### Recommendations:
1. **Security First:**
   - Use strong, unique passwords
   - Enable SSL/TLS (automatically handled by Caddy)
   - Restrict access to management interfaces
   - Regular backups

2. **Scaling:**
   - Processor replicas: 5-10 (based on load)
   - Worker replicas: 2-5 (based on order volume)

3. **Monitoring:**
   - Enable Telegram logging
   - Install Portainer for container monitoring
   - Set up external monitoring (Grafana/Prometheus)

4. **High Availability:**
   - Consider external managed databases (RDS, etc.)
   - Use external object storage (S3, etc.)
   - Multiple application servers behind load balancer

### Installation:
```bash
./install.sh
```

Use production-grade configurations:
- Strong passwords (at least 16 characters)
- Real domain names with proper DNS
- Enable Telegram logging
- Configure appropriate replica counts

### Post-Installation Checklist:
- [ ] Verify all services are healthy: `docker compose ps`
- [ ] Check SSL certificates are issued: `docker compose logs caddy`
- [ ] Test all application endpoints
- [ ] Configure firewall rules
- [ ] Set up backup strategy
- [ ] Configure monitoring alerts
- [ ] Document access credentials securely
- [ ] Test disaster recovery procedures

---

## Distributed Setup

Scale across multiple servers.

### Architecture Example:
```
┌─────────────────┐
│  Load Balancer  │
│   (External)    │
└────────┬────────┘
         │
    ┌────┴─────┬──────────────┬──────────────┐
    │          │              │              │
┌───▼────┐ ┌──▼─────┐ ┌──────▼────┐ ┌───────▼─────┐
│ App    │ │ App    │ │ Database  │ │   Storage   │
│ Server │ │ Server │ │  Server   │ │   Server    │
│   #1   │ │   #2   │ │           │ │   (MinIO)   │
└────────┘ └────────┘ └────┬──────┘ └─────────────┘
                           │
                    ┌──────┴─────┬────────┐
                    │            │        │
               ┌────▼────┐  ┌────▼───┐ ┌─▼──────┐
               │PostgreSQL│  │RabbitMQ│ │ Redis │
               └──────────┘  └────────┘ └────────┘
```

### Server Configurations:

#### Database Server:
```bash
./install.sh
# Select: PostgreSQL, PgAdmin, Portainer only
```

#### Storage Server:
```bash
./install.sh
# Select: MinIO, Portainer only
```

#### Message Broker Server:
```bash
./install.sh
# Select: RabbitMQ, Redis, Redis Insight, Portainer only
```

#### Application Server #1 & #2:
```bash
./install.sh
# Select: WebApp, Client App, Processor, Worker, Jobs, Caddy
# Configure high replica counts
# Point to external database/storage/queue servers
```

### Network Configuration:
1. Set up private network between servers
2. Configure security groups/firewall:
   - App servers: Expose 80, 443 only
   - Database server: Expose 5432 to app servers only
   - RabbitMQ: Expose 5672 to app servers only
   - Redis: Expose 6379 to app servers only
   - MinIO: Expose 9000 to app servers only

3. Update `.env` files on app servers to point to external services:
   ```bash
   # On application servers, edit .env
   POSTGRES_HOST=10.0.1.10  # Database server IP
   RABBITMQ_HOST=10.0.2.10  # Message broker IP
   REDIS_HOST=10.0.2.10     # Redis IP
   MINIO_ENDPOINT=10.0.3.10:9000  # Storage server IP
   ```

---

## Troubleshooting Common Issues

### Issue: Docker service not starting
```bash
# Check service status
sudo systemctl status docker

# Restart Docker service
sudo systemctl restart docker
```

### Issue: Permission denied when running Docker commands
```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Log out and back in, or run:
newgrp docker
```

### Issue: Services not accessible via domains
1. Check DNS configuration:
   ```bash
   nslookup your-domain.com
   ```

2. Verify Caddy is running:
   ```bash
   docker compose logs caddy
   ```

3. Check if ports are open:
   ```bash
   sudo netstat -tulpn | grep -E ':(80|443)'
   ```

### Issue: Out of memory errors
1. Check memory usage:
   ```bash
   free -h
   docker stats
   ```

2. Reduce replica counts in `.env`:
   ```bash
   PROCESSER_REPLICAS=2
   ORDER_WORKER_REPLICAS=1
   ```

3. Restart services:
   ```bash
   docker compose down
   docker compose up -d
   ```

### Issue: Database connection errors
1. Verify PostgreSQL is running:
   ```bash
   docker compose ps postgres
   ```

2. Check database logs:
   ```bash
   docker compose logs postgres
   ```

3. Test connection:
   ```bash
   docker compose exec postgres psql -U $POSTGRES_USER -d $POSTGRES_DB
   ```

---

## Backup and Recovery

### Creating Backups

#### Database Backup:
```bash
# Create backup directory
mkdir -p backups

# Backup PostgreSQL
docker compose exec postgres pg_dump -U $POSTGRES_USER $POSTGRES_DB > backups/db_backup_$(date +%Y%m%d_%H%M%S).sql
```

#### Configuration Backup:
```bash
# Backup is automatically created by install.sh
# Manual backup:
cp .env .env.backup_$(date +%Y%m%d_%H%M%S)
cp docker-compose.yml docker-compose.yml.backup_$(date +%Y%m%d_%H%M%S)
```

### Restoring from Backup

#### Restore Database:
```bash
# Copy backup file to container
docker compose cp backups/db_backup_20240101_120000.sql postgres:/tmp/

# Restore database
docker compose exec postgres psql -U $POSTGRES_USER $POSTGRES_DB < /tmp/db_backup_20240101_120000.sql
```

---

## Advanced Configuration

### Custom Docker Compose Overrides

Create `docker-compose.override.yml` for custom configurations:

```yaml
version: '3.8'

services:
  webapp:
    environment:
      - CUSTOM_SETTING=value
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
```

### Environment-Specific Configurations

Create environment-specific files:
- `.env.development`
- `.env.staging`
- `.env.production`

Use with:
```bash
docker compose --env-file .env.production up -d
```

---

## Performance Tuning

### Database Performance:
```bash
# Increase PostgreSQL max connections
# Edit docker-compose.yml, add to postgres service:
command: postgres -c max_connections=200
```

### Application Performance:
```bash
# Adjust replica counts based on load
PROCESSER_REPLICAS=10
ORDER_WORKER_REPLICAS=5

# Apply changes
docker compose up -d --scale processor=$PROCESSER_REPLICAS
```

### Redis Performance:
```bash
# Add to docker-compose.yml redis service
command: redis-server --maxmemory 1gb --maxmemory-policy allkeys-lru
```

---

## Security Best Practices

1. **Change default passwords** - Always use strong, unique passwords
2. **Use secrets management** - Consider Docker secrets or external vaults
3. **Enable firewall** - Only expose necessary ports
4. **Regular updates** - Keep Docker images updated
5. **Monitor logs** - Enable Telegram logging and review regularly
6. **Backup regularly** - Automate database and configuration backups
7. **Use HTTPS only** - Caddy handles this automatically
8. **Limit access** - Use VPN or IP whitelisting for admin interfaces
9. **Audit access** - Review who has access to servers and services
10. **Test recovery** - Regularly test backup restoration procedures
