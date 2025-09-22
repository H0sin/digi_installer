#!/bin/bash

# Generate self-signed SSL certificate for Digi

mkdir -p ssl

if [ ! -f "ssl/nginx-selfsigned.crt" ]; then
    echo "Generating self-signed SSL certificate..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout ssl/nginx-selfsigned.key \
        -out ssl/nginx-selfsigned.crt \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"
    echo "SSL certificate generated in ssl/"
else
    echo "SSL certificate already exists"
fi