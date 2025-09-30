# Digital Bot Infrastructure

This repository contains the Docker Compose setup for the Digital Bot application with all its required services and proper domain configuration.

**📖 Documentation:**
- [Quick Start Guide](QUICKSTART.md) - Get started in 5 minutes
- [English Documentation](README.md) (this file)
- [راهنمای فارسی (Persian Guide)](README_FA.md)
- [Detailed Installation Guide](INSTALLATION_GUIDE.md)

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

- Linux operating system (Ubuntu 20.04+ recommended)
- Minimum 2 CPU cores (4+ recommended)
- Minimum 2GB RAM (4GB+ recommended)
- Minimum 20GB free disk space
- DNS records configured for all domains pointing to your server
- SSL certificates will be automatically obtained via Let's Encrypt

**Note:** The installation script can automatically install Docker and Docker Compose if they are not present.

## Quick Start

### One-Line Installation (Fastest)

Install with a single command (works with or without sudo):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/H0sin/digi_installer/main/install.sh)
```

Or using wget:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/H0sin/digi_installer/main/install.sh)
```

**For private repositories**, first set your GitHub credentials:

```bash
# Clone with GitHub credentials
git clone https://github.com/H0sin/digi_installer.git
cd digi_installer
./install.sh
```

### Automated Installation (Recommended)

Run the interactive installation script:

```bash
./install.sh
```

The installation script will:
- ✅ Check system requirements (CPU, RAM, disk space)
- ✅ Install Docker and Docker Compose if needed
- ✅ Interactively ask which services to install
- ✅ Collect all required configuration values
- ✅ Generate `.env` file with your configuration
- ✅ Update `Caddyfile` based on selected services
- ✅ Validate configuration
- ✅ Deploy and start all services
- ✅ Backup existing configuration if present

### Manual Installation

1. **Copy the example environment file:**
   ```bash
   cp .env.example .env
   ```

2. **Edit `.env` file with your configuration:**
   ```bash
   nano .env
   ```

3. **Start all services:**
   ```bash
   docker compose up -d
   ```

4. **Check service status:**
   ```bash
   docker compose ps
   ```

## Configuration

### Interactive Installation

The `install.sh` script provides an interactive setup experience:

#### Service Selection
You can choose which services to install:
- PostgreSQL database and PgAdmin
- RabbitMQ message broker
- Redis cache and Redis Insight
- MinIO object storage
- Portainer (Docker management)
- Main web application
- Client application (React frontend)
- Processor service (with configurable replicas)
- Order worker service (with configurable replicas)
- Jobs service
- Caddy reverse proxy

#### Configuration Collection
The script will interactively ask for:
- **Project name**: Custom name for your Docker Compose project
- **Domain configuration**: Main domain and subdomains for all services
- **SSL/TLS settings**: Email for Let's Encrypt, optional Cloudflare API token
- **Docker images**: Custom image names for your application services
- **Service credentials**: Passwords for PostgreSQL, RabbitMQ, Redis, PgAdmin, MinIO
- **Telegram logging**: Optional integration for application logging
- **Scale settings**: Number of replicas for processor and worker services

#### Features
- ✅ **Automatic backup**: Backs up existing configuration before making changes
- ✅ **Validation**: Validates all configuration before deployment
- ✅ **Security**: Sets proper file permissions on sensitive files
- ✅ **Auto-deployment**: Automatically deploys services after configuration
- ✅ **DNS configuration**: Generates proper Caddyfile for your domains

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