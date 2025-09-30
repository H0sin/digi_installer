# Quick Start Guide

## Installation in 5 Minutes

### Option 1: One-Line Installation (Fastest)

Install directly from GitHub with a single command:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/H0sin/digi_installer/main/install.sh)
```

Or using wget:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/H0sin/digi_installer/main/install.sh)
```

**Requirements:**
- Run as a regular user (not root)
- Requires `sudo` privileges for Docker installation and service management
- Ubuntu 20.04+ or Debian-based systems

**For Private Repositories:**
```bash
# Using Personal Access Token
git clone https://YOUR_USERNAME:YOUR_TOKEN@github.com/H0sin/digi_installer.git

# Or using SSH
git clone git@github.com:H0sin/digi_installer.git
```

---

### Option 2: Clone and Install

### Step 1: Clone Repository
```bash
git clone https://github.com/H0sin/digi_installer.git
cd digi_installer
```

### Step 2: Run Installation Script
```bash
chmod +x install.sh
./install.sh
```

### Step 3: Follow Interactive Prompts

The script will guide you through:

1. **System Check**: Automatic verification of requirements
2. **Docker Installation**: Automatic if not present
3. **Service Selection**: Choose what to install
4. **Configuration**: Enter your settings
5. **Deployment**: Automatic setup and launch

### Step 4: Access Your Services

After installation, access your services at:
- Main Application: `https://yourdomain.com`
- Client App: `https://client.yourdomain.com`
- PgAdmin: `https://pgadmin.yourdomain.com`
- Portainer: `https://portainer.yourdomain.com`
- RabbitMQ: `https://rabbitmq.yourdomain.com`
- Redis Insight: `https://redis.yourdomain.com`
- MinIO Console: `https://minio.yourdomain.com`
- MinIO Files: `https://files.yourdomain.com`

---

## Example: Full Installation

```bash
$ ./install.sh

# System checks...
✅ Docker detected
✅ System requirements met
✅ Backup created

# Service selection (answer Y to all for full stack)
Install PostgreSQL database? (Y/n): Y
Install PgAdmin? (Y/n): Y
Install RabbitMQ? (Y/n): Y
Install Redis? (Y/n): Y
Install Redis Insight? (Y/n): Y
Install MinIO? (Y/n): Y
Install Portainer? (Y/n): Y
Install main web application? (Y/n): Y
Install client application? (Y/n): Y
Install processor service? (Y/n): Y
Number of processor replicas (1-10) [5]: 5
Install order worker service? (Y/n): Y
Number of order worker replicas (1-10) [2]: 2
Install jobs service? (Y/n): Y
Install Caddy reverse proxy? (Y/n): Y

# Configuration
Project name [digitalbot]: myapp
Main domain: example.com
Email for SSL: admin@example.com
PostgreSQL password: ********
RabbitMQ password: ********
Redis password: ********
...

# Deployment
✅ Configuration generated
✅ Validation passed
✅ Services deployed
🎉 Installation complete!
```

---

## What Gets Installed

### Infrastructure Services
- **PostgreSQL**: Primary database
- **PgAdmin**: Database management UI
- **RabbitMQ**: Message queue
- **Redis**: Cache and session storage
- **Redis Insight**: Redis management UI
- **MinIO**: Object storage (S3-compatible)

### Application Services
- **Web Application**: Main ASP.NET Core backend
- **Client Application**: React frontend
- **Processor Service**: Background processing (5 replicas)
- **Order Worker**: Order processing (2 replicas)
- **Jobs Service**: Scheduled tasks

### Supporting Services
- **Caddy**: Reverse proxy with automatic SSL
- **Portainer**: Docker management UI

### Networking
- `digitalbot_web`: Public network for web services
- `digitalbot_internal`: Private network for backend services

### Volumes
- `postgres-data`: Database storage
- `minio-data`: Object storage
- `caddy-data`: SSL certificates
- `portainer-data`: Portainer configuration

---

## Pre-Installation Checklist

Before running the installation:

- [ ] Server is running Ubuntu 20.04+ or similar
- [ ] Minimum 2GB RAM, 2 CPU cores, 20GB disk
- [ ] DNS records point to your server IP
- [ ] Ports 80 and 443 are available
- [ ] You have sudo privileges
- [ ] You have prepared strong passwords
- [ ] You have a valid email for SSL certificates

---

## Post-Installation Checklist

After installation completes:

- [ ] All services are running: `docker compose ps`
- [ ] SSL certificates are issued: `docker compose logs caddy`
- [ ] Main application is accessible
- [ ] Client application loads correctly
- [ ] Admin interfaces are accessible
- [ ] Database connection works
- [ ] Message queue is operational
- [ ] Redis cache is working
- [ ] Object storage is functional

---

## Common Issues and Solutions

### Issue: Script stops at "Install PostgreSQL database?"
**Solution**: The script is waiting for your input. Type `Y` or `N` and press Enter.

### Issue: Docker not found
**Solution**: The script will offer to install Docker. Answer `Y` to proceed.

### Issue: Permission denied
**Solution**: Make sure the script is executable:
```bash
chmod +x install.sh
```

### Issue: Services not starting
**Solution**: Check logs:
```bash
docker compose logs
```

### Issue: Domain not accessible
**Solution**: 
1. Verify DNS: `nslookup yourdomain.com`
2. Check firewall: `sudo ufw status`
3. View Caddy logs: `docker compose logs caddy`

---

## Next Steps

After successful installation:

1. **Security**:
   - Change default passwords
   - Set up firewall rules
   - Configure backup strategy

2. **Monitoring**:
   - Set up Telegram logging
   - Configure alerts
   - Monitor resource usage

3. **Scaling**:
   - Adjust replica counts based on load
   - Consider distributed architecture
   - Implement load balancing

4. **Maintenance**:
   - Regular backups
   - Update Docker images
   - Monitor disk space
   - Review logs

---

## Getting Help

- **Documentation**: See `INSTALLATION_GUIDE.md` for detailed scenarios
- **Persian Guide**: See `README_FA.md` for Persian documentation
- **Logs**: Check `docker compose logs [service]`
- **Status**: Run `docker compose ps`
- **GitHub Issues**: Report problems at repository issues page

---

## Useful Commands

```bash
# View all services
docker compose ps

# View logs
docker compose logs -f

# Restart services
docker compose restart

# Stop all services
docker compose down

# Start all services
docker compose up -d

# Update services
docker compose pull && docker compose up -d

# Scale services
docker compose up -d --scale processor=10

# Backup database
docker compose exec postgres pg_dump -U username dbname > backup.sql

# Access PostgreSQL
docker compose exec postgres psql -U username -d dbname

# View resource usage
docker stats
```

---

## Support

For questions and support:
- Read the documentation
- Check the logs
- Open an issue on GitHub
- Review `INSTALLATION_GUIDE.md` for detailed scenarios
