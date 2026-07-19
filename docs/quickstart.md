# Quick Start

## 5-Minute Boot

```bash
# 1. Download (2.3 GB)
wget https://github.com/ash-linux/ash/releases/latest/download/ash-2025.01.15.iso

# 2. Verify (REQUIRED)
sha256sum -c ash-2025.01.15.iso.sha256
minisign -Vm ash-2025.01.15.iso -P RWQf6LRCGA9i52mlZT2k5B5Y5Q5Y5Q5Y5Q5Y5Q5Y5Q5Y5Q5Y5Q5Y5Q5Y= -x ash-2025.01.15.iso.minisig

# 3. Import to hypervisor
# VMware: File → New → "Install from disc or image" → Select ISO
# VirtualBox: New → Arch Linux (64-bit) → 8GB RAM → Storage → Optical Drive → Select ISO
# Parallels: File → New → "Install from DVD or image file" → Select ISO
# QEMU: see below

# 4. Boot → Desktop in ~45s → Terminal opens → Code!
ollama run llama3.1
```

## QEMU/KVM Quick Commands

```bash
# Live boot (no persistence)
qemu-system-x86_64 \
  -enable-kvm -cpu host -m 4G -smp 4 \
  -drive file=ash-2025.01.15.iso,media=cdrom,readonly=on \
  -boot d -display gtk -serial stdio \
  -device virtio-net-pci,netdev=net0 \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -device virtio-gpu-pci

# Install to disk (persistent)
qemu-img create -f qcow2 ash-disk.qcow2 50G
qemu-system-x86_64 \
  -enable-kvm -cpu host -m 8G -smp 4 \
  -drive file=ash-2025.01.15.iso,media=cdrom,readonly=on \
  -drive file=ash-disk.qcow2,format=qcow2 \
  -boot d -display gtk \
  -device virtio-net-pci,netdev=net0 \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -device virtio-gpu-pci
```

## GPU Passthrough

| Hypervisor | Command / Setting |
|------------|-------------------|
| **VMware** | Settings → Display → "Accelerate 3D graphics" + "Use host GPU" |
| **VirtualBox** | `VBoxManage modifyvm "ash" --gpupassthrough on` |
| **Parallels** | Hardware → Graphics → "Auto" (Metal on Apple Silicon) |
| **QEMU/KVM** | `-device vfio-pci,host=XX:XX.X` (requires IOMMU, VFIO) |

Ollama and llama.cpp auto-detect: AMD ROCm, NVIDIA CUDA, Apple Metal.

## First Boot Checklist

- [ ] Terminal opens automatically
- [ ] `ollama run llama3.1` works
- [ ] `ai-model-selector` opens GUI
- [ ] Qdrant at `http://localhost:6333`
- [ ] VS Code + Continue extension ready
- [ ] Snapshots: `snapper list`

## Persistence

- `/home` = Btrfs subvolume `@home` (survives reboots)
- `/var/lib/qdrant` = `@qdrant` subvolume (excluded from snapshots)
- Models in `~/.ollama` persist
- Weekly auto-update creates pre/post snapshots

## Troubleshooting

```bash
# Debug logs
journalctl -u iso-firstboot -u ollama-pull-default -u qdrant -f

# Collect debug archive
iso-debug-issue  # creates ~/iso-debug-*.tar.gz

# Report issue
iso-report-issue  # opens GitHub with template + attaches logs
```