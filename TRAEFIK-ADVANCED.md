# 🔧 Advanced Traefik Configuration Guide

This guide covers advanced configuration options for Traefik in the Digital Bot installer.

## 📋 Table of Contents

- [Certificate Resolvers](#certificate-resolvers)
- [Middleware Configuration](#middleware-configuration)
- [Service Discovery](#service-discovery)
- [Security Best Practices](#security-best-practices)
- [DNS Providers](#dns-providers)
- [Monitoring & Metrics](#monitoring--metrics)
- [Troubleshooting](#troubleshooting)

## 🔐 Certificate Resolvers

### HTTP-01 Challenge (Default)

Best for most single-domain setups:

```yaml
# In docker-compose.yml, Traefik command section
- --certificatesresolvers.httpresolver.acme.email=${TRAEFIK_ACME_EMAIL}
- --certificatesresolvers.httpresolver.acme.storage=/letsencrypt/acme.json
- --certificatesresolvers.httpresolver.acme.httpchallenge.entrypoint=web
```

**Requirements:**
- Ports 80 and 443 must be publicly accessible
- Domain must resolve to your server's public IP

### DNS-01 Challenge (For Wildcards)

Enables wildcard certificates (`*.yourdomain.com`):

```yaml
# Set in .env
TRAEFIK_CERT_RESOLVER=dnsresolver
ACME_DNS_PROVIDER=cloudflare
CLOUDFLARE_API_TOKEN=your_cloudflare_token

# In docker-compose.yml, Traefik command section
- --certificatesresolvers.dnsresolver.acme.email=${TRAEFIK_ACME_EMAIL}
- --certificatesresolvers.dnsresolver.acme.storage=/letsencrypt/acme.json
- --certificatesresolvers.dnsresolver.acme.dnschallenge=true
- --certificatesresolvers.dnsresolver.acme.dnschallenge.provider=${ACME_DNS_PROVIDER}
```

## 🛡️ Middleware Configuration

### Basic Authentication

Protect admin interfaces with basic auth:

```bash
# Generate password hash
htpasswd -nbB admin yourpassword

# Add to .env
TRAEFIK_ADMIN_AUTH="admin:$2y$10$..."

# In traefik/dynamic/middlewares.yml
admin-auth:
  basicAuth:
    users:
      - "${TRAEFIK_ADMIN_AUTH}"
```

### Rate Limiting

Configure different rate limits for different services:

```yaml
# In traefik/dynamic/middlewares.yml
http:
  middlewares:
    api-rate-limit:
      rateLimit:
        average: 50
        period: 1m
        burst: 100
    
    admin-rate-limit:
      rateLimit:
        average: 10
        period: 1m
        burst: 20
```

### IP Whitelisting

Restrict access to admin interfaces:

```yaml
# In traefik/dynamic/middlewares.yml
admin-ip-whitelist:
  ipWhiteList:
    sourceRange:
      - "10.0.0.0/8"      # Private networks
      - "172.16.0.0/12"
      - "192.168.0.0/16"
      - "1.2.3.4/32"      # Specific admin IP
```

### Compression

Enable response compression:

```yaml
compression:
  compress:
    excludedContentTypes:
      - "text/event-stream"
```

## 🔍 Service Discovery

### Docker Labels

Add these labels to any Docker service for automatic discovery:

```yaml
services:
  your-service:
    labels:
      # Enable Traefik
      - traefik.enable=true
      
      # Router configuration
      - traefik.http.routers.yourservice.rule=Host(`your-subdomain.yourdomain.com`)
      - traefik.http.routers.yourservice.entrypoints=websecure
      - traefik.http.routers.yourservice.tls=true
      - traefik.http.routers.yourservice.tls.certresolver=httpresolver
      
      # Middleware chain
      - traefik.http.routers.yourservice.middlewares=default-security@file,rate-limit@file
      
      # Service configuration
      - traefik.http.services.yourservice.loadbalancer.server.port=8080
      - traefik.http.services.yourservice.loadbalancer.healthcheck.path=/health
      - traefik.http.services.yourservice.loadbalancer.healthcheck.interval=30s
```

### File Provider

For external services or advanced routing, use file-based configuration in `traefik/dynamic/services.yml`:

```yaml
http:
  routers:
    external-api:
      rule: "Host(`api.yourdomain.com`)"
      service: "external-api-service"
      entryPoints:
        - "websecure"
      tls:
        certResolver: "httpresolver"
      middlewares:
        - "default-security@file"
        - "api-rate-limit@file"

  services:
    external-api-service:
      loadBalancer:
        servers:
          - url: "https://external-api.example.com"
        healthCheck:
          path: "/health"
          interval: "30s"
```

## 🔒 Security Best Practices

### TLS Configuration

Enhanced TLS settings in `traefik/dynamic/middlewares.yml`:

```yaml
tls:
  options:
    secure:
      minVersion: VersionTLS13
      sniStrict: true
      cipherSuites:
        - TLS_AES_256_GCM_SHA384
        - TLS_CHACHA20_POLY1305_SHA256
      curvePreferences:
        - X25519
        - secp384r1
```

### Security Headers

Comprehensive security headers:

```yaml
security-headers:
  headers:
    # HSTS
    stsSeconds: 31536000
    stsIncludeSubdomains: true
    stsPreload: true
    
    # Content Security Policy
    contentSecurityPolicy: "default-src 'self'; script-src 'self' 'unsafe-inline'"
    
    # Other security headers
    frameDeny: true
    contentTypeNosniff: true
    browserXssFilter: true
    referrerPolicy: "strict-origin-when-cross-origin"
    
    # Permissions Policy
    permissionsPolicy: "geolocation=(), microphone=(), camera=()"
    
    # Hide server information
    customResponseHeaders:
      Server: ""
      X-Powered-By: ""
```

## 🌐 DNS Providers

### Cloudflare

```bash
# Required scopes: Zone:Zone:Read, Zone:DNS:Edit
CLOUDFLARE_API_TOKEN=your_token
```

### AWS Route53

```bash
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key
AWS_REGION=us-east-1
```

### DigitalOcean

```bash
DO_AUTH_TOKEN=your_do_token
```

### Google Cloud DNS

```bash
GCE_PROJECT=your_project_id
GCE_SERVICE_ACCOUNT_FILE=/path/to/service-account.json
```

## 📊 Monitoring & Metrics

### Prometheus Metrics

Enable metrics collection:

```yaml
# In docker-compose.yml, Traefik command section
- --metrics.prometheus=true
- --metrics.prometheus.addEntryPointsLabels=true
- --metrics.prometheus.addServicesLabels=true
- --metrics.prometheus.manualrouting=true
```

Access metrics at: `http://your-server:8080/metrics`

### Key Metrics to Monitor

- `traefik_http_requests_total` - Total HTTP requests
- `traefik_http_request_duration_seconds` - Request duration
- `traefik_service_requests_total` - Requests per service
- `traefik_entrypoint_requests_total` - Requests per entrypoint

### Grafana Dashboard

Import Traefik dashboard ID: `11462` for comprehensive monitoring.

## 🐞 Troubleshooting

### Common Issues

1. **Certificate Not Issued**
   ```bash
   # Check ACME logs
   docker compose logs traefik | grep -i acme
   
   # Verify DNS resolution
   nslookup yourdomain.com
   
   # Check port accessibility
   curl -I http://yourdomain.com/.well-known/acme-challenge/test
   ```

2. **Service Not Accessible**
   ```bash
   # Check if service is discovered
   curl -s http://localhost:8080/api/http/routers | jq '.[] | select(.rule | contains("yourdomain"))'
   
   # Verify service health
   docker compose ps
   ```

3. **Middleware Not Applied**
   ```bash
   # Check middleware configuration
   curl -s http://localhost:8080/api/http/middlewares | jq
   
   # Verify file provider is loaded
   docker compose logs traefik | grep -i "provider.file"
   ```

### Debug Mode

Enable debug logging:

```yaml
# In docker-compose.yml
- --log.level=DEBUG
- --accesslog=true
- --accesslog.filepath=/var/log/traefik/access.log
```

### API Access

Access Traefik API for debugging:

```bash
# List all routers
curl -s http://localhost:8080/api/http/routers | jq

# List all services
curl -s http://localhost:8080/api/http/services | jq

# List all middlewares
curl -s http://localhost:8080/api/http/middlewares | jq
```

## 🚀 Performance Optimization

### Connection Pooling

```yaml
# In service labels
- traefik.http.services.yourservice.loadbalancer.passhostheader=true
- traefik.http.services.yourservice.loadbalancer.responseforwarding.flushinterval=1ms
```

### Circuit Breaker

```yaml
circuit-breaker:
  circuitBreaker:
    expression: "NetworkErrorRatio() > 0.30"
    checkPeriod: "3s"
    fallbackDuration: "10s"
    recoveryDuration: "3s"
```

### Sticky Sessions

```yaml
- traefik.http.services.yourservice.loadbalancer.sticky.cookie=true
- traefik.http.services.yourservice.loadbalancer.sticky.cookie.name=server
- traefik.http.services.yourservice.loadbalancer.sticky.cookie.secure=true
```

---

For more advanced configurations, refer to the [Official Traefik Documentation](https://doc.traefik.io/traefik/).