# Digital Bot Infrastructure

This repository contains the Docker Compose setup for the Digital Bot application with all its required services and proper domain configuration.

## Services and Domains

The application consists of the following services with their respective domains:

| Service | Domain | Description |
|---------|--------|-------------|
| Main Application | `be-unavailable.com` | ASP.NET Core web application |
| Traefik Dashboard | `traefik.be-unavailable.com` | Reverse proxy dashboard |
| PgAdmin | `pgadmin.be-unavailable.com` | PostgreSQL administration |
| Portainer | `portainer.be-unavailable.com` | Docker container management |
| RabbitMQ Management | `rabbitmq.be-unavailable.com` | Message broker dashboard |
| React Client App | `client.be-unavailable.com` | Frontend application |
| Redis Insight | `redis-insight.be-unavailable.com` | Redis database management |

## Prerequisites

- Docker and Docker Compose installed
- DNS records configured for all domains pointing to your server
- SSL certificates will be automatically obtained via Let's Encrypt

## Quick Start

1. **Setup Infrastructure:**
   ```bash
   ./setup.sh
   ```

2. **Start all services:**
   ```bash
   docker compose up -d
   ```

3. **Check service status:**
   ```bash
   docker compose ps
   ```

## Configuration

### Environment Variables

Key configuration is in the `.env` file:

- **Domain Configuration**: All service domains are configured with `be-unavailable.com`
- **Authentication**: Basic auth is configured for admin interfaces
- **SSL/TLS**: Let's Encrypt certificates with both HTTP-01 and DNS-01 challenges
- **Database**: PostgreSQL with pgAdmin
- **Message Queue**: RabbitMQ with management UI
- **Caching**: Redis with Redis Insight

### Authentication

Admin interfaces are protected with basic authentication:
- **Username**: `admin`
- **Password**: `Alis1378`

Dashboard interfaces use:
- **Username**: `ali`
- **Password**: `ali`

### SSL Certificates

The setup supports both:
- **HTTP-01 Challenge**: For individual domain certificates
- **DNS-01 Challenge**: For wildcard certificates (requires Cloudflare API token)

## Monitoring and Health Checks

All services include health checks and will restart automatically if they fail.

## Networks

- `digitalbot_web`: External network for web-facing services
- `digitalbot_internal`: Internal network for service communication

## Volumes

- `postgres-data`: PostgreSQL database storage
- `portainer-data`: Portainer configuration
- `traefik-letsencrypt`: SSL certificate storage

## Troubleshooting

1. **Check service logs:**
   ```bash
   docker compose logs [service_name]
   ```

2. **Verify network connectivity:**
   ```bash
   docker network ls | grep digitalbot
   ```

3. **Test domain resolution:**
   ```bash
   nslookup be-unavailable.com
   ```

4. **Restart services:**
   ```bash
   docker compose restart
   ```

## Security

- All services use HTTPS with automatic SSL certificates
- Admin interfaces are protected with basic authentication
- Internal services are isolated in a separate network
- Security headers are configured via Traefik
- Rate limiting is applied to public endpoints