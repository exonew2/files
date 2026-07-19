#!/usr/bin/env bash
# user-data-worker.sh — Worker node initialization for ash AI cluster
set -euo pipefail

exec > /var/log/ash-cluster-worker-init.log 2>&1

CLUSTER_NAME="${cluster_name}"
NODE_TYPE="${node_type}"

pacman -Sy --noconfirm archlinux-keyring
pacman -S --noconfirm docker consul

systemctl enable --now docker

# Configure Consul agent
cat > /etc/consul.d/client.json << CONSUL
{
  "server": false,
  "datacenter": "ash",
  "data_dir": "/opt/consul",
  "log_level": "INFO",
  "bind_addr": "0.0.0.0",
  "retry_join": ["provider=aws tag_key=ash-cluster tag_value=${CLUSTER_NAME}"],
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

    # Register with Consul
    consul services register \
      -name "ollama-$(hostname)" \
      -port 11434 \
      -tag "ollama" \
      -tag "${CLUSTER_NAME}"
    ;;

  qdrant)
    docker run -d --name qdrant --restart always \
      -p 6333:6333 -p 6334:6334 \
      -v qdrant-data:/qdrant/storage \
      qdrant/qdrant:latest

    consul services register \
      -name "qdrant-$(hostname)" \
      -port 6333 \
      -tag "vectordb" \
      -tag "${CLUSTER_NAME}"
    ;;
esac

echo "${NODE_TYPE} node initialized for cluster: ${CLUSTER_NAME}"
