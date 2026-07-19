# Justfile — Common tasks for ash development

# Variables
VERSION := $(shell date +%Y.%m.%d)
ARCH := "x86_64"

# Default target
default: help

help:
	@echo "ash — Arch Snapshot Hypervisor"
	@echo ""
	@echo "Core Build Targets:"
	@echo "  build-iso          Build ISO locally (requires root, Arch host)"
	@echo "  build-iso-arm64    Build ARM64 ISO via cross-compilation"
	@echo "  test-iso           Test ISO boot in QEMU"
	@echo "  build-vm           Build all VM formats via Packer"
	@echo "  build-cloud        Build cloud images (AWS/GCP/Azure)"
	@echo "  vagrant            Build Vagrant box"
	@echo ""
	@echo "Distribution Targets:"
	@echo "  sign               Generate signatures + SLSA provenance"
	@echo "  distribute         Upload to all mirrors & registries"
	@echo "  ash-container      Build OCI container image from ISO"
	@echo "  ash-rpi4           Build Raspberry Pi 4 image"
	@echo "  ash-rpi5           Build Raspberry Pi 5 image"
	@echo "  ash-wsl            Build WSL2 distribution tarball"
	@echo ""
	@echo "Cloud Targets:"
	@echo "  cluster-up         Spin up local AI cluster (ash-cluster up --nodes 3)"
	@echo "  cluster-down       Tear down local AI cluster"
	@echo "  cluster-status     Show cluster status"
	@echo "  push-aws           Deploy ISO to AWS as AMI"
	@echo "  push-gcp           Deploy ISO to GCP as custom image"
	@echo "  push-azure         Deploy ISO to Azure as managed image"
	@echo "  push-cloud         Deploy to all clouds"
	@echo ""
	@echo "Terraform:"
	@echo "  tf-aws             Deploy ash AI cluster on AWS"
	@echo "  tf-gcp             Deploy ash AI cluster on GCP"
	@echo "  tf-azure           Deploy ash AI cluster on Azure"
	@echo ""
	@echo "Pipeline Targets:"
	@echo "  release            Full release pipeline (build + sign + distribute)"
	@echo "  release-arm64      Full ARM64 release pipeline"
	@echo ""
	@echo "Other:"
	@echo "  landing            Build and preview landing page"
	@echo "  clean              Clean build artifacts"
	@echo ""

# ─── Core Build Targets ──────────────────────────────────────────────

# Build ISO (requires root on Arch Linux)
build-iso:
	sudo ./scripts/build-iso.sh $(VERSION)

# Build ARM64 ISO via cross-compilation
build-iso-arm64:
	./scripts/cross-build-arm64.sh $(VERSION)

# Test ISO boot
test-iso:
	./scripts/test-iso.sh out/ash-$(VERSION).iso

# Build VM formats
build-vm:
	cd packer && packer init . && packer build -var "version=$(VERSION)" -var "iso_path=../out/ash-$(VERSION).iso" ash-iso.pkr.hcl

# Build cloud images
build-cloud:
	cd packer && for f in aws-ami.pkr.hcl gcp-image.pkr.hcl azure-image.pkr.hcl; do \
	  [ -f "$$f" ] && packer build -var "version=$(VERSION)" -var "iso_path=../out/ash-$(VERSION).iso" "$$f" || true; \
	done

# Build Vagrant box
vagrant:
	cd packer && packer init . && packer build -var "version=$(VERSION)" -var "iso_path=../out/ash-$(VERSION).iso" vagrant-box.pkr.hcl

# ─── Distribution Targets ────────────────────────────────────────────

# Generate signatures and SLSA provenance
sign:
	./scripts/sign-provenance.sh $(VERSION)

# Distribute to all mirrors and registries
distribute:
	./scripts/distribute.sh $(VERSION)

# Build OCI container image from ISO (push to GHCR)
ash-container:
	@echo "Building OCI container image ash:$(VERSION)..."
	cat /tmp/Dockerfile.ash 2>/dev/null || printf 'FROM scratch\nADD out/ash-$(VERSION).iso /ash.iso\nADD out/ash-$(VERSION).iso.sha256 /ash.iso.sha256\n' > /tmp/Dockerfile.ash
	docker buildx build --platform linux/amd64 -f /tmp/Dockerfile.ash -t ghcr.io/ash-linux/ash:$(VERSION) -t ghcr.io/ash-linux/ash:latest --push . || echo "Push requires GHCR_TOKEN"

# Build Raspberry Pi 4 image
ash-rpi4:
	@echo "Building RPi4 image..."
	qemu-img convert -f iso -O raw out/ash-$(VERSION)-arm64.iso out/ash-$(VERSION)-rpi4.img 2>/dev/null || echo "ARM64 ISO required"
	gzip -c out/ash-$(VERSION)-rpi4.img > out/ash-$(VERSION)-rpi4.img.gz 2>/dev/null || true

# Build Raspberry Pi 5 image
ash-rpi5:
	@echo "Building RPi5 image..."
	qemu-img convert -f iso -O raw out/ash-$(VERSION)-arm64.iso out/ash-$(VERSION)-rpi5.img 2>/dev/null || echo "ARM64 ISO required"
	gzip -c out/ash-$(VERSION)-rpi5.img > out/ash-$(VERSION)-rpi5.img.gz 2>/dev/null || true

# Build WSL2 distribution tarball
ash-wsl:
	@echo "Building WSL2 tarball..."
	mkdir -p /tmp/ash-wsl
	cat > /tmp/ash-wsl/Dockerfile << 'EOF'
FROM archlinux:latest
RUN pacman -Sy --noconfirm base linux-firmware sudo zsh fish openssh docker ollama qdrant && \
    pacman -Scc --noconfirm && \
    useradd -m -G wheel,docker -s /bin/zsh aiuser && \
    echo 'aiuser ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers.d/aiuser && \
    rm -f /etc/machine-id
CMD ["/bin/zsh"]
EOF
	docker build -t ash-wsl-builder /tmp/ash-wsl
	docker export $$(docker create ash-wsl-builder) | gzip > out/ash-$(VERSION).wsl
	@echo "WSL2 tarball: out/ash-$(VERSION).wsl"

# ─── Cloud Targets ───────────────────────────────────────────────────

# Spin up local AI cluster
cluster-up:
	./scripts/ash-cluster/ash-cluster up --nodes 3

# Tear down local AI cluster
cluster-down:
	./scripts/ash-cluster/ash-cluster down

# Show cluster status
cluster-status:
	./scripts/ash-cluster/ash-cluster status

# Deploy ISO to AWS as AMI
push-aws:
	./scripts/push-to-cloud.sh $(VERSION) --aws

# Deploy ISO to GCP as custom image
push-gcp:
	./scripts/push-to-cloud.sh $(VERSION) --gcp

# Deploy ISO to Azure as managed image
push-azure:
	./scripts/push-to-cloud.sh $(VERSION) --azure

# Deploy to all clouds
push-cloud:
	./scripts/push-to-cloud.sh $(VERSION) --all

# ─── Terraform ───────────────────────────────────────────────────────

# Deploy ash AI cluster on AWS
tf-aws:
	cd terraform/aws-ash-cluster && terraform init && terraform apply -auto-approve

# Deploy ash AI cluster on GCP
tf-gcp:
	cd terraform/gcp-ash-cluster && terraform init && terraform apply -auto-approve

# Deploy ash AI cluster on Azure
tf-azure:
	cd terraform/azure-ash-cluster && terraform init && terraform apply -auto-approve

# ─── Pipeline Targets ────────────────────────────────────────────────

# Full release pipeline (x86_64)
release: build-iso test-iso sign build-vm build-cloud distribute
	@echo "Release $(VERSION) complete!"

# Full ARM64 release pipeline
release-arm64: build-iso-arm64 sign distribute
	@echo "ARM64 release $(VERSION) complete!"

# ─── Other ───────────────────────────────────────────────────────────

# Landing page
landing:
	cd landing-page && npm install && npm run dev

landing-build:
	cd landing-page && PUBLIC_VERSION=$(VERSION) npm install && npm run build

landing-preview:
	cd landing-page && npm run preview

# Clean
clean:
	rm -rf out/
	rm -rf packer/output-*/
	rm -rf landing-page/dist/ landing-page/.astro/
	rm -rf /tmp/ash-*-build-*/
	-docker compose -f scripts/ash-cluster/docker-compose.yml down -v 2>/dev/null || true
	docker system prune -f 2>/dev/null || true

.PHONY: help build-iso build-iso-arm64 test-iso build-vm build-cloud vagrant \
  sign distribute ash-container ash-rpi4 ash-rpi5 ash-wsl \
  cluster-up cluster-down cluster-status \
  push-aws push-gcp push-azure push-cloud \
  tf-aws tf-gcp tf-azure \
  release release-arm64 \
  landing landing-build landing-preview clean
