# 🤖 Digital Bot

[![.NET](https://img.shields.io/badge/.NET-9.0-512BD4?logo=dotnet)](https://dotnet.microsoft.com/)
[![ASP.NET Core](https://img.shields.io/badge/ASP.NET%20Core-9.0-512BD4?logo=dotnet)](https://asp.net/)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker)](https://docker.com/)
[![RabbitMQ](https://img.shields.io/badge/RabbitMQ-3.13-FF6600?logo=rabbitmq)](https://rabbitmq.com/)
[![SQL Server](https://img.shields.io/badge/SQL%20Server-2022-CC2927?logo=microsoft-sql-server)](https://www.microsoft.com/sql-server)
[![Traefik](https://img.shields.io/badge/Traefik-v3.0-24A1C1?logo=traefik)](https://traefik.io/)

A comprehensive ASP.NET Core web application with microservices architecture, featuring message queuing, database management, and containerized deployment with automatic SSL certificates.

## 🌟 Features

- **Microservices Architecture**: Scalable and maintainable service-oriented design
- **Message Queue Processing**: RabbitMQ integration for reliable message handling
- **Automatic SSL**: Let's Encrypt integration via Traefik
- **Database Management**: SQL Server with Adminer interface
- **Container Orchestration**: Docker Compose for easy deployment
- **Monitoring**: Portainer for container management
- **Worker Scaling**: Configurable worker replicas
- **Health Checks**: Built-in health monitoring

## 🏗️ Architecture

```mermaid
graph TB
    subgraph "External Access"
        U[Users] --> T[Traefik Reverse Proxy]
        A[Admin] --> T
    end

    subgraph "Application Layer"
        T --> W[Web Application]
        T --> AD[Adminer]
        T --> P[Portainer]
    end

    subgraph "Processing Layer"
        W --> R[RabbitMQ]
        R --> WK[Worker Services]
    end

    subgraph "Data Layer"
        W --> DB[SQL Server]
        WK --> DB
        AD --> DB
    end

    subgraph "Management"
        P --> D[Docker Engine]
    end
```

## 🚀 Quick Start

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/) & [Docker Compose](https://docs.docker.com/compose/install/)
- [Git](https://git-scm.com/)
- Domain name (for SSL certificates)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/H0sin/digital_bot_installer.git
   cd digital_bot_installer
   ```

2. **Configure environment variables**
   ```bash
   cp .env.example .env
   ```

3. **Update the `.env` file** with your configuration:
   ```bash
   nano .env
   ```

4. **Start the application**
   ```bash
   docker-compose up -d
   ```

5. **Access the application**
   - Main App: `https://your-domain.com`
   - Database Admin: `https://dbadmin.your-domain.com`
   - Container Management: `https://monitor.your-domain.com`

## ⚙️ Configuration

### Environment Variables

Create a `.env` file in the project root:

```env
# --- Docker Compose Settings ---
COMPOSE_PROJECT_NAME=digitalbot

# --- Image Settings ---
WEBAPP_IMAGE=ghcr.io/H0sin/digital_bot_installer:latest
WORKER_IMAGE=ghcr.io/H0sin/digital_bot_installer-worker:latest
WORKER_REPLICAS=5 

# --- Database Settings ---
DB_USER=sa
DB_PASSWORD=YourStrongPassword123!
DB_NAME=DigitalBot_DB

# --- Domain Settings ---
DOMAIN=your-domain.com
DB_ADMIN_DOMAIN=dbadmin.your-domain.com
PORTAINER_DOMAIN=monitor.your-domain.com
ACME_EMAIL=your-email@example.com

# --- RabbitMQ Settings ---
RABBITMQ_USER=admin
RABBITMQ_PASS=your-rabbitmq-password
```

### Configuration Reference

| Variable | Description | Required | Default |
|----------|-------------|----------|----------|
| `COMPOSE_PROJECT_NAME` | Docker Compose project name | ✅ | `digitalbot` |
| `WEBAPP_IMAGE` | Web application Docker image | ✅ | - |
| `WORKER_IMAGE` | Worker service Docker image | ✅ | - |
| `WORKER_REPLICAS` | Number of worker instances | ❌ | `1` |
| `DB_PASSWORD` | Database SA password | ✅ | - |
| `DB_NAME` | Database name | ✅ | - |
| `DOMAIN` | Main application domain | ✅ | - |
| `DB_ADMIN_DOMAIN` | Database admin subdomain | ✅ | - |
| `PORTAINER_DOMAIN` | Container management subdomain | ✅ | - |
| `ACME_EMAIL` | Email for SSL certificates | ✅ | - |
| `RABBITMQ_USER` | RabbitMQ username | ✅ | - |
| `RABBITMQ_PASS` | RabbitMQ password | ✅ | - |

## 🏃‍♂️ Development

### Project Structure

```
digital_bot_installer/
├── Api/                        # Web API project
├── Application/               # Application layer
├── Contracts/                 # Shared contracts
├── Data/                      # Data access layer
├── Domain/                    # Domain models
├── Worker/                    # Background worker service
├── .github/                   # GitHub Actions workflows
├── docker-compose.yml         # Docker services configuration
├── docker-compose.override.yml # Development overrides
├── .env                       # Environment variables
├── .dockerignore             # Docker ignore rules
├── .gitignore                # Git ignore rules
├── DigitalBot.sln            # Solution file
└── README.md                 # This file
```

### Local Development

1. **Start infrastructure services**
   ```bash
   docker-compose up -d db rabbitmq
   ```

2. **Run the application locally**
   ```bash
   dotnet run --project Api
   ```

3. **Run worker service**
   ```bash
   dotnet run --project Worker
   ```

### Building Docker Images

```bash
# Build web application
docker build -t your-registry/digital_bot_installer:latest -f Api/Dockerfile .

# Build worker service
docker build -t your-registry/digital_bot_installer-worker:latest -f Worker/Dockerfile .
```

## 🔧 Services Overview

### Web Application (API)
- **Port**: 8080 (internal)
- **Framework**: ASP.NET Core 9.0
- **Features**: RESTful API, Authentication, Authorization

### Worker Service
- **Replicas**: Configurable (default: 1)
- **Purpose**: Background task processing
- **Queue**: RabbitMQ integration

### Database (SQL Server)
- **Version**: 2022 Latest
- **Port**: 1433 (internal)
- **Features**: Health checks, persistent storage

### Message Queue (RabbitMQ)
- **Version**: 3.13 with Management
- **Ports**: 5672 (AMQP), 15672 (Management)
- **Features**: Message persistence, management UI

### Reverse Proxy (Traefik)
- **Version**: v3.0
- **Ports**: 80, 443, 8080
- **Features**: Automatic SSL, Load balancing

## 📊 Monitoring & Management

### Service Health Monitoring

```bash
# Check all services status
docker-compose ps

# View service logs
docker-compose logs -f [service-name]

# Monitor resource usage
docker stats
```

### RabbitMQ Management
- **URL**: `http://your-server-ip:15672`
- **Credentials**: Use `RABBITMQ_USER` and `RABBITMQ_PASS`

### Database Management
- **URL**: `https://dbadmin.your-domain.com`
- **Server**: `db`
- **Credentials**: Use `DB_USER` and `DB_PASSWORD`

### Container Management
- **URL**: `https://monitor.your-domain.com`
- **Features**: Container monitoring, log viewing, resource management

## 🚀 Deployment

### Production Deployment

1. **Prepare the server**
   ```bash
   # Update system
   sudo apt update && sudo apt upgrade -y

   # Install Docker
   curl -fsSL https://get.docker.com -o get-docker.sh
   sudo sh get-docker.sh

   # Install Docker Compose
   sudo curl -L "https://github.com/docker/compose/releases/download/v2.21.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
   sudo chmod +x /usr/local/bin/docker-compose
   ```

2. **Configure DNS**
   - Point your domain to your server IP
   - Configure subdomains for admin interfaces

3. **Deploy application**
   ```bash
   git clone https://github.com/H0sin/digital_bot_installer.git
   cd digital_bot_installer
   cp .env.example .env
   # Edit .env with your configuration
   docker-compose up -d
   ```

### Scaling Workers

```bash
# Scale to 10 workers
docker-compose up -d --scale worker=10

# Or update WORKER_REPLICAS in .env and restart
docker-compose up -d
```

### SSL Certificate Management

Traefik automatically manages SSL certificates through Let's Encrypt. Ensure:
- Your domains point to your server
- Ports 80 and 443 are accessible
- Email in `ACME_EMAIL` is valid

## 🛠️ Troubleshooting

### Common Issues

<details>
<summary>SSL Certificate Issues</summary>

- Check domain DNS settings
- Verify email in `ACME_EMAIL`
- Check Traefik logs: `docker-compose logs traefik`
- Ensure ports 80 and 443 are open
</details>

<details>
<summary>Database Connection Issues</summary>

- Verify `DB_PASSWORD` is correct
- Check database health: `docker-compose exec db /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "password" -Q "SELECT 1"`
- Review connection strings in application logs
</details>

<details>
<summary>RabbitMQ Connection Issues</summary>

- Check RabbitMQ service status: `docker-compose logs rabbitmq`
- Verify credentials in `.env`
- Check network connectivity between services
</details>

### Useful Commands

```bash
# Restart specific service
docker-compose restart [service-name]

# View real-time logs
docker-compose logs -f --tail=100

# Clean up unused resources
docker system prune -a

# Backup database
docker exec digitalbot-db /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "password" -Q "BACKUP DATABASE [DigitalBot_DB] TO DISK = N'/var/opt/mssql/backup.bak'"
```

## 📚 Technology Stack

- **Backend**: ASP.NET Core 9.0, C# 13.0
- **Database**: Microsoft SQL Server 2022
- **Message Queue**: RabbitMQ 3.13
- **Reverse Proxy**: Traefik v3.0
- **Containerization**: Docker & Docker Compose
- **SSL**: Let's Encrypt (automatic)
- **Monitoring**: Portainer, Adminer

## 🔒 Security

### Security Features

- **HTTPS Only**: Automatic redirect from HTTP to HTTPS
- **SSL Certificates**: Automatic Let's Encrypt certificates
- **Network Isolation**: Internal network for service communication
- **Database Security**: Database only accessible from internal network
- **Container Security**: Non-root user containers where possible

### Security Best Practices

1. **Use strong passwords** for all services
2. **Regularly update** Docker images
3. **Monitor logs** for suspicious activity
4. **Backup data** regularly
5. **Keep SSL certificates** up to date

## 🤝 Contributing

We welcome contributions! Please follow these steps:

1. **Fork the repository**
2. **Create a feature branch**
   ```bash
   git checkout -b feature/amazing-feature
   ```
3. **Make your changes**
4. **Add tests** if applicable
5. **Commit your changes**
   ```bash
   git commit -m 'Add amazing feature'
   ```
6. **Push to the branch**
   ```bash
   git push origin feature/amazing-feature
   ```
7. **Open a Pull Request**

### Development Guidelines

- Follow C# coding standards
- Write meaningful commit messages
- Add documentation for new features
- Ensure all tests pass
- Update README if needed

## 📊 Performance

### Recommended Resources

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | 2 cores | 4+ cores |
| RAM | 4GB | 8GB+ |
| Storage | 20GB | 50GB+ |
| Network | 100Mbps | 1Gbps |

### Performance Monitoring

```bash
# Monitor resource usage
docker stats

# Check database performance
docker exec digitalbot-db /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "password" -Q "SELECT * FROM sys.dm_os_performance_counters WHERE counter_name LIKE '%CPU%'"

# Monitor RabbitMQ queues
curl -u admin:password http://localhost:15672/api/queues
```

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [ASP.NET Core](https://asp.net/) team for the amazing framework
- [RabbitMQ](https://rabbitmq.com/) for reliable messaging
- [Traefik](https://traefik.io/) for automatic SSL and load balancing
- [Docker](https://docker.com/) for containerization

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/H0sin/digital_bot_installer/issues)
- **Discussions**: [GitHub Discussions](https://github.com/H0sin/digital_bot_installer/discussions)
- **Email**: support@your-domain.com

---

<p align="center">
  Made with ❤️ by the Digital Bot Team
</p>
