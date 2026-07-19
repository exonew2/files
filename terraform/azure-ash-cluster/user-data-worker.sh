#!/usr/bin/env bash
set -euo pipefail

exec > /var/log/ash-cluster-worker-init.log 2>&1

NODE_TYPE="${node_type}"
CLUSTER_NAME="${cluster_name}"

pacman -Sy --noconfirm archlinux-keyring
pacman -S --noconfirm docker consul

systemctl enable --now docker

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

case "${NODE_TYPE}" in
  ollama)
    docker run -d --name ollama --restart always \
      -p 11434:11434 \
      -v ollama-data:/root/.ollama \
      -e OLLAMA_NUM_PARALLEL=4 \
      ollama/ollama:latest
    ;;
  qdrant)
    docker run -d --name qdrant --restart always \
      -p 6333:6333 -p 6334:6334 \
      -v qdrant-data:/qdrant/storage \
      qdrant/qdrant:latest
    ;;
esac
