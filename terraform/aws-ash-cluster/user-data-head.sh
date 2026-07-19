#!/usr/bin/env bash
# user-data-head.sh — Head node initialization for ash AI cluster
set -euo pipefail

exec > /var/log/ash-cluster-head-init.log 2>&1

CLUSTER_NAME="${cluster_name}"

pacman -Sy --noconfirm archlinux-keyring
pacman -S --noconfirm docker docker-compose consul nginx qdrant

systemctl enable --now docker consul

# Configure Consul agent (client mode)
cat > /etc/consul.d/client.json << CONSUL
{
  "server": false,
  "datacenter": "ash",
  "data_dir": "/opt/consul",
  "log_level": "INFO",
  "enable_script_checks": true,
  "bind_addr": "0.0.0.0",
  "retry_join": ["provider=aws tag_key=ash-cluster tag_value=${CLUSTER_NAME}"],
  "ports": {
    "dns": 8600,
    "http": 8500,
    "serf_lan": 8301,
    "serf_wan": 8302
  }
}
CONSUL

systemctl restart consul

# Configure nginx as API router
cat > /etc/nginx/nginx.conf << 'NGINX'
events {}
http {
    upstream ollama {
        least_conn;
        server 127.0.0.1:11434;
    }
    upstream qdrant {
        server 127.0.0.1:6333;
    }
    server {
        listen 80;
        location /v1/ { proxy_pass http://ollama; proxy_set_header Host $host; }
        location /qdrant/ { proxy_pass http://qdrant/; }
        location /health { return 200 "OK\n"; }
        location / { return 200 "ash AI Cluster: ${CLUSTER_NAME}\n"; }
    }
}
NGINX

systemctl enable --now nginx

# Pull AI models
docker pull ollama/ollama:latest
docker pull qdrant/qdrant:latest

echo "ash-cluster head node initialized: ${CLUSTER_NAME}"
