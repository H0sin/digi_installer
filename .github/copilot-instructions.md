# Digital Bot Installer

Digital Bot Installer is a Docker-based deployment system for a comprehensive ASP.NET Core web application with microservices architecture, featuring PostgreSQL database, RabbitMQ message queuing, Redis caching, and containerized services with automatic SSL certificates via Traefik or HAProxy.

Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.

## Working Effectively

### Prerequisites and Setup
- **Docker Required**: Docker Engine v20.10+ and Docker Compose v2.0+
- **Container Registry Access**: Application images are private on GitHub Container Registry (ghcr.io/h0sin/*) and require authentication
- **Domain Requirements**: Valid domain names needed for SSL certificate generation

### Quick Infrastructure Test (Public Images Only)
- Bootstrap basic services: `docker compose up -d postgres rabbitmq redis portainer`
- **NEVER CANCEL**: Infrastructure startup takes 11-15 seconds for image pulls, then 30-40 seconds for health checks. Set timeout to 120+ seconds minimum.
- Monitor health: `docker compose ps` - wait for "healthy" status on all services
- Clean up: `docker compose down`

### Full Application Deployment (Requires Authentication)
- **Authentication Note**: Main application images (webapp, client-app, processor, order-worker) are private and will fail with "unauthorized" errors without proper GitHub Container Registry credentials
- Complete deployment: `docker compose up -d`
- **NEVER CANCEL**: Full deployment with image pulls can take 5-10 minutes depending on network speed. Set timeout to 20+ minutes.
- Monitor services: `docker compose ps --format "table {{.Service}}\t{{.Status}}"`

### Alternative Deployment with Traefik
- Validate Traefik configuration: `docker compose -f docker-compose.yml -f docker-compose.traefik.yml config --services`
- **NEVER CANCEL**: Traefik overlay validation takes <1 second, but full deployment with SSL certificate generation can take 5-10 minutes. Set timeout to 20+ minutes.
- Deploy with Traefik: `docker compose -f docker-compose.yml -f docker-compose.traefik.yml up -d`
- **Note**: Traefik requires Cloudflare API tokens and proper DNS configuration for automatic SSL

## Validation and Testing

### Infrastructure Health Monitoring
- **Critical Timing**: PostgreSQL becomes healthy in ~20 seconds, RabbitMQ takes 30-35 seconds, Redis is healthy within 10 seconds
- Real-time status monitoring:
  ```bash
  for i in {1..30}; do 
    echo "Check $i:"; 
    docker compose ps --format "table {{.Service}}\t{{.Status}}"; 
    sleep 2; 
  done
  ```

### Service Access Points (when fully deployed)
- **Main Application**: `https://${DOMAIN}` (ASP.NET Core API)
- **Client Application**: `https://${CLIENT_APP_DOMAIN}` (React frontend)
- **Database Admin**: `https://${PGADMIN_DOMAIN}` (pgAdmin interface)
- **Message Queue**: `https://${RABBITMQ_DOMAIN}` (RabbitMQ Management UI)
- **Container Management**: `https://${PORTAINER_DOMAIN}` (Portainer dashboard)
- **Cache Insights**: `https://${REDISINSIGHT_DOMAIN}` (RedisInsight)

### Manual Validation Requirements
- **PostgreSQL Test**: `docker exec postgres pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}`
- **Redis Test**: `docker exec redis redis-cli -a ${REDIS_PASSWORD} ping`
- **RabbitMQ Test**: Access management UI or check `docker compose logs rabbitmq` for successful startup
- **Container Health**: All services must show "healthy" status before proceeding

## Configuration Management

### Environment Configuration
- **Primary Config**: `.env` file contains all environment variables
- **No .env.example**: Repository contains a working `.env` with real credentials - handle with care
- **Critical Variables**: 
  - `POSTGRES_PASSWORD`, `RABBITMQ_PASS`, `REDIS_PASSWORD` for service authentication
  - `*_DOMAIN` variables for routing and SSL certificates
  - `CLOUDFLARE_API_TOKEN` for Traefik DNS challenge

### Service Architecture
- **Web Network**: External-facing services (webapp, client-app, pgadmin, portainer, rabbitmq, redisinsight)
- **Internal Network**: Backend communication (postgres, redis, message processing)
- **Image Sources**: 
  - Public: postgres:16-alpine, rabbitmq:3-management, redis:7-alpine, portainer/portainer-ce:latest
  - Private: ghcr.io/h0sin/digital-* (requires authentication)

## Troubleshooting and Monitoring

### Common Failure Points
- **Image Authentication**: Private images return "unauthorized" - check GitHub Container Registry access
- **Health Check Delays**: RabbitMQ takes longest to become healthy (~35 seconds)
- **Port Conflicts**: Default ports 80/443 for HAProxy, 5432 for PostgreSQL exposed externally
- **SSL Certificate Issues**: Traefik requires valid DNS records and open port 80 for Let's Encrypt HTTP-01 challenge

### Diagnostic Commands
- Service logs: `docker compose logs -f [service-name]`
- Resource usage: `docker stats`
- Network inspection: `docker network ls` and `docker network inspect digitalbot_web`
- Volume inspection: `docker volume ls` and `docker volume inspect digitalbot_postgres-data`

### Performance Expectations
- **Infrastructure Services**: 15-second startup, 40-second health check completion
- **Public Image Pulls**: 2-4 seconds per service (Redis, Portainer, PostgreSQL, RabbitMQ)
- **Private Image Deployment**: Not testable without authentication
- **Service Shutdown**: 1-2 seconds per service, RabbitMQ may take up to 10 seconds

## Development Workflow

### Configuration Testing
- **Always validate first**: `docker compose config --services` (should list 11 services)
- **Traefik overlay test**: `docker compose -f docker-compose.yml -f docker-compose.traefik.yml config --services`
- **Environment validation**: Check `.env` file for required variables before deployment

### Safe Development Practices
- **Start incrementally**: Begin with infrastructure services only
- **Monitor health checks**: Never proceed until all services show "healthy" status
- **Use appropriate timeouts**: Infrastructure: 2+ minutes, Full deployment: 20+ minutes
- **Clean up properly**: Always run `docker compose down` to remove containers and networks

### Deployment Modes
1. **HAProxy Mode** (default): Standard deployment with HAProxy reverse proxy
2. **Traefik Mode**: Overlay deployment with automatic SSL via Let's Encrypt and Cloudflare DNS

## Common Tasks

### Repository Structure
```
/home/runner/work/digi_installer/digi_installer/
├── .env                           # Environment configuration
├── docker-compose.yml             # Main service definitions
├── docker-compose.traefik.yml     # Traefik overlay configuration
├── haproxy/haproxy.cfg.template   # HAProxy configuration template
├── traefik/dynamic/middlewares.yml # Traefik middleware definitions
├── certs/                         # SSL certificate storage
├── entrypoint.sh                  # HAProxy environment substitution script
└── Readme.MD                      # Comprehensive documentation
```

### Key Environment Variables Reference
```env
COMPOSE_PROJECT_NAME=digitalbot
POSTGRES_USER=hossein
POSTGRES_PASSWORD=[configured]
POSTGRES_DB=digitalbot_db
RABBITMQ_USER=hossein
RABBITMQ_PASS=[configured]
REDIS_PASSWORD=[configured]
DOMAIN=be-unavailable.com
CLOUDFLARE_API_TOKEN=[configured]
```

**CRITICAL REMINDER**: This is a deployment repository, not source code. The actual applications are containerized and stored in private registries. Focus on Docker Compose orchestration, service health monitoring, and configuration management rather than application development.