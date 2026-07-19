#!/usr/bin/env bash
# push-to-cloud.sh — Deploy ash ISO to AWS/GCP/Azure as ready-to-use VM images
# Usage: ./push-to-cloud.sh <version> [--aws|--gcp|--azure|--all]
# Example: ./push-to-cloud.sh 2025.01.1 --all

set -euo pipefail

VERSION="${1:?Version required (e.g., 2025.01.1)}"
TARGET="${2:---all}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."
OUT_DIR="$ROOT_DIR/out"
ISO_FILE="$OUT_DIR/ash-${VERSION}.iso"
ARM64_ISO_FILE="$OUT_DIR/ash-${VERSION}-arm64.iso"
PACKER_DIR="$ROOT_DIR/packer"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log() { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err() { echo -e "${RED}[✗]${NC} $*" >&2; }

check_prereqs() {
  local missing=0
  for cmd in packer jq; do
    command -v "$cmd" &>/dev/null || { err "$cmd not found"; missing=1; }
  done
  return "$missing"
}

check_cloud_cli() {
  case "$1" in
    aws)   command -v aws &>/dev/null || { err "AWS CLI not found"; return 1; } ;;
    gcp)   command -v gcloud &>/dev/null || { err "gcloud CLI not found"; return 1; } ;;
    azure) command -v az &>/dev/null || { err "Azure CLI not found"; return 1; } ;;
  esac
}

push_aws() {
  log "Deploying ash-${VERSION} to AWS..."

  if [[ ! -f "$PACKER_DIR/aws-ami.pkr.hcl" ]]; then
    warn "aws-ami.pkr.hcl not found — building from ISO"
    check_cloud_cli aws || return 1

    # Import ISO as snapshot-backed AMI
    local bucket="${AWS_BUCKET:-ash-iso-import}"
    local role_name="${AWS_ROLE_NAME:-vmimport}"

    aws s3 cp "$ISO_FILE" "s3://${bucket}/ash-${VERSION}.iso"
    aws s3 cp "${ISO_FILE}.sha256" "s3://${bucket}/ash-${VERSION}.iso.sha256"

    cat > /tmp/import-task.json << JSON
{
  "Description": "ash-${VERSION}",
  "Format": "iso",
  "UserBucket": { "S3Bucket": "${bucket}", "S3Key": "ash-${VERSION}.iso" }
}
JSON

    local task_id
    task_id=$(aws ec2 import-snapshot --disk-container file:///tmp/import-task.json --query 'ImportTaskId' --output text)
    log "Import task: $task_id"

    while true; do
      local status
      status=$(aws ec2 describe-import-snapshot-tasks --import-task-ids "$task_id" --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.Status' --output text)
      log "Snapshot status: $status"
      [[ "$status" == "completed" ]] && break
      sleep 30
    done

    local snapshot_id
    snapshot_id=$(aws ec2 describe-import-snapshot-tasks --import-task-ids "$task_id" --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.SnapshotId' --output text)

    # Register AMI
    local ami_id
    ami_id=$(aws ec2 register-image \
      --name "ash-${VERSION}" \
      --description "ash — Arch Snapshot Hypervisor v${VERSION}" \
      --architecture x86_64 \
      --root-device-name /dev/sda1 \
      --block-device-mappings "DeviceName=/dev/sda1,Ebs={SnapshotId=${snapshot_id},VolumeSize=50,VolumeType=gp3}" \
      --virtualization-type hvm \
      --ena-support \
      --boot-mode uefi \
      --query 'ImageId' --output text)

    log "AMI registered: $ami_id"

    # Make public
    aws ec2 modify-image-attribute \
      --image-id "$ami_id" \
      --launch-permission "Add={Group=all}"

    echo "$ami_id" > "$OUT_DIR/ash-${VERSION}-ami.txt"
    log "AMI is now public: $ami_id"
  else
    log "Using existing Packer template for AWS"
    packer init "$PACKER_DIR"
    packer build \
      -var "version=$VERSION" \
      -var "iso_path=$ISO_FILE" \
      "$PACKER_DIR/aws-ami.pkr.hcl"
  fi

  log "AWS deployment complete!"
}

push_gcp() {
  log "Deploying ash-${VERSION} to GCP..."
  check_cloud_cli gcp || return 1

  local project="${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
  local image_name="ash-${VERSION//./-}"

  if gcloud compute images describe "$image_name" --project="$project" &>/dev/null; then
    log "Image $image_name already exists"
  else
    # Create image from raw disk
    local raw_disk="$OUT_DIR/ash-${VERSION}.img"
    if [[ ! -f "$raw_disk" ]]; then
      warn "Raw disk not found, converting ISO..."
      qemu-img convert -f iso -O raw "$ISO_FILE" "$raw_disk"
    fi

    # Compress and upload
    gzip -c "$raw_disk" > "${raw_disk}.gz"

    local bucket="${GCP_BUCKET:-ash-images-uploads}"
    gsutil cp "${raw_disk}.gz" "gs://${bucket}/ash-${VERSION}.img.gz"

    # Create image
    gcloud compute images create "$image_name" \
      --project="$project" \
      --source-uri="gs://${bucket}/ash-${VERSION}.img.gz" \
      --architecture=X86_64 \
      --family="ash-linux" \
      --description="ash — Arch Snapshot Hypervisor v${VERSION}" \
      --guest-os-features=GVNIC,SEV_CAPABLE \
      --storage-location="${GCP_STORAGE_LOCATION:-us}"

    # Make public
    gcloud compute images add-iam-policy-binding "$image_name" \
      --project="$project" \
      --member="allAuthenticatedUsers" \
      --role="roles/compute.imageUser"

    log "GCP image created: $image_name"
  fi

  log "GCP deployment complete!"
}

push_azure() {
  log "Deploying ash-${VERSION} to Azure..."
  check_cloud_cli azure || return 1

  local resource_group="${AZURE_RG:-ash-images}"
  local image_name="ash-${VERSION//./-}"
  local storage_account="${AZURE_STORAGE:-ashimages}"

  az group create --name "$resource_group" --location "${AZURE_LOCATION:-eastus}" 2>/dev/null || true

  if az image show --resource-group "$resource_group" --name "$image_name" &>/dev/null; then
    log "Image $image_name already exists"
  else
    # Upload VHD
    if [[ ! -f "$OUT_DIR/ash-${VERSION}.vhd" ]]; then
      local raw_disk="$OUT_DIR/ash-${VERSION}.img"
      [[ -f "$raw_disk" ]] || qemu-img convert -f iso -O raw "$ISO_FILE" "$raw_disk"
      qemu-img convert -f raw -O vpc "$raw_disk" "$OUT_DIR/ash-${VERSION}.vhd"
    fi

    az storage container create --name images --account-name "$storage_account" 2>/dev/null || true
    az storage blob upload \
      --account-name "$storage_account" \
      --container-name images \
      --file "$OUT_DIR/ash-${VERSION}.vhd" \
      --name "ash-${VERSION}.vhd"

    # Create managed image
    az image create \
      --resource-group "$resource_group" \
      --name "$image_name" \
      --os-type Linux \
      --source "https://${storage_account}.blob.core.windows.net/images/ash-${VERSION}.vhd" \
      --hyper-v-generation V2

    log "Azure image created: $image_name"
  fi

  log "Azure deployment complete!"
}

# Main
log "Push-to-Cloud: ash-${VERSION}"

check_prereqs

case "$TARGET" in
  --aws|aws)
    push_aws
    ;;
  --gcp|gcp)
    push_gcp
    ;;
  --azure|azure)
    push_azure
    ;;
  --all|all|*)
    push_aws || warn "AWS push failed"
    push_gcp || warn "GCP push failed"
    push_azure || warn "Azure push failed"
    ;;
esac

log "All cloud deployments complete!"
echo ""
echo "  AWS:  $(cat "$OUT_DIR/ash-${VERSION}-ami.txt" 2>/dev/null || echo 'Not deployed')"
echo "  GCP:  ash-${VERSION//./-}"
echo "  AZ:   ash-${VERSION//./-}"
