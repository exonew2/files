#!/usr/bin/env bash
# cloud-firstboot.sh — Cloud environment detection and first-boot configuration
# Runs once on first boot to auto-configure for cloud or bare-metal

set -euo pipefail

log() { echo "[cloud-firstboot] $*"; }
warn() { echo "[cloud-firstboot] WARNING: $*"; }

detect_cloud() {
  # AWS: IMDSv1/v2
  if curl -sf --max-time 2 http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null; then
    local identity
    identity=$(curl -sf http://169.254.169.254/latest/dynamic/instance-identity/document 2>/dev/null || echo "")
    if echo "$identity" | grep -q "amazonaws"; then
      echo "aws"
      return
    fi
  fi

  # GCP: metadata server
  if curl -sf --max-time 2 -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/id 2>/dev/null; then
    echo "gcp"
    return
  fi

  # Azure: IMDS
  if curl -sf --max-time 2 -H "Metadata: true" http://169.254.169.254/metadata/instance?api-version=2021-02-01 2>/dev/null; then
    echo "azure"
    return
  fi

  echo "on-prem"
}

configure_aws() {
  log "Configuring for AWS"

  # Enable ENA (Elastic Network Adapter) for enhanced networking
  if lsmod | grep -q ena || modprobe ena 2>/dev/null; then
    echo "ena" >> /etc/modules-load.d/cloud-optimizations.conf
    log "ENA driver enabled"
  fi

  # Enable EFA (Elastic Fabric Adapter) if available
  if modprobe efa 2>/dev/null; then
    echo "efa" >> /etc/modules-load.d/cloud-optimizations.conf
    log "EFA driver enabled"
  fi

  # Configure cloud-init for EC2
  cat > /etc/cloud/cloud.cfg.d/10_ash_datasource.cfg << 'CFG'
datasource_list: [Ec2, ConfigDrive, NoCloud]
datasource:
  Ec2:
    metadata_urls: ["http://169.254.169.254"]
    timeout: 60
    max_wait: 120
CFG

  # NVMe instance storage
  if ls /dev/nvme* 2>/dev/null; then
    mkdir -p /mnt/ephemeral
    for dev in /dev/nvme[0-9]n1; do
      if [[ -b "$dev" ]] && ! mount | grep -q "$dev"; then
        mkfs.ext4 "$dev" 2>/dev/null && mount "$dev" /mnt/ephemeral || true
        break
      fi
    done
    log "Ephemeral NVMe storage mounted"
  fi
}

configure_gcp() {
  log "Configuring for GCP"

  # Enable gVNIC
  if modprobe gve 2>/dev/null; then
    echo "gve" >> /etc/modules-load.d/cloud-optimizations.conf
    log "gVNIC driver enabled"
  fi

  # Configure cloud-init for GCE
  cat > /etc/cloud/cloud.cfg.d/10_ash_datasource.cfg << 'CFG'
datasource_list: [GCE, ConfigDrive, NoCloud]
datasource:
  GCE:
    timeout: 60
    max_wait: 120
CFG

  # GCP OS Login agent
  systemctl enable --now google-oslogin-cache 2>/dev/null || true
}

configure_azure() {
  log "Configuring for Azure"

  # Enable hv_* drivers for Hyper-V
  for mod in hv_storvsc hv_netvsc hv_vmbus hid_hyperv; do
    modprobe "$mod" 2>/dev/null && echo "$mod" >> /etc/modules-load.d/cloud-optimizations.conf || true
  done
  log "Hyper-V drivers enabled"

  # Configure cloud-init for Azure
  cat > /etc/cloud/cloud.cfg.d/10_ash_datasource.cfg << 'CFG'
datasource_list: [Azure, ConfigDrive, NoCloud]
datasource:
  Azure:
    timeout: 60
    max_wait: 120
CFG

  # Azure Linux Agent
  systemctl enable --now waagent 2>/dev/null || true
}

main() {
  log "Starting cloud first-boot detection..."

  local cloud
  cloud=$(detect_cloud)
  log "Detected environment: $cloud"

  mkdir -p /etc/cloud/cloud.cfg.d /etc/modules-load.d

  case "$cloud" in
    aws)
      configure_aws
      echo "cloud=aws" > /etc/ash-cloud-env
      ;;
    gcp)
      configure_gcp
      echo "cloud=gcp" > /etc/ash-cloud-env
      ;;
    azure)
      configure_azure
      echo "cloud=azure" > /etc/ash-cloud-env
      ;;
    on-prem)
      log "On-premises / bare-metal detected — no cloud optimizations needed"
      echo "cloud=on-prem" > /etc/ash-cloud-env
      ;;
  esac

  # Common: enable guest agent regardless
  systemctl enable --now qemu-guest-agent 2>/dev/null || true

  # Configure cluster auto-scaling if cluster mode requested
  if [[ -f /etc/ash-cluster/config.json ]]; then
    log "Cluster mode detected — starting auto-scaling agent"
    systemctl enable --now ash-cluster-agent 2>/dev/null || true
  fi

  # Mark first boot as complete
  touch /var/lib/ash-cloud-firstboot-done
  log "Cloud first-boot configuration complete"
}

main "$@"
