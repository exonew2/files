#!/usr/bin/env bash
set -euo pipefail

exec > /var/log/ash-cluster-head-init.log 2>&1

CLUSTER_NAME="${cluster_name}"

pacman -Sy --noconfirm archlinux-keyring
pacman -S --noconfirm docker docker-compose consul nginx

systemctl enable --now docker consul

# Consul
cat > /etc/consul.d/client.json << CONSUL
{
  "server": false,
  "datacenter": "ash",
  "data_dir": "/opt/consul",
  "log_level": "INFO",
  "retry_join": ["provider=azure tag_name=ash-cluster tag_value=${CLUSTER_NAME}"],
  "ports": { "dns": 8600, "http": 8500, "serf_lan": 8301, "serf_wan": 8302 }
}
CONSUL

systemctl restart consul

# Nginx router
cat > /etc/nginx/nginx.conf << 'NGINX'
events { }
http {
    upstream ollama { least_conn; server 127.0.0.1:11434; }
    upstream qdrant { server 127.0.0.1:6333; }
    server {
        listen 80;
        location /v1/ { proxy_pass http://ollama; }
        location /qdrant/ { proxy_pass http://qdrant/; }
        location /health { return 200 "OK\n"; }
    }
}
NGINX

systemctl enable --now nginx

docker pull ollama/ollama:latest
docker pull qdrant/qdrant:latest
