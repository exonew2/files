---
title: GPU Passthrough Guide
description: Configure GPU passthrough for VMware, VirtualBox, Parallels, and QEMU/KVM to accelerate local LLMs with Ollama and llama.cpp.
order: 3
---

## VMware Fusion / Workstation

1. **Host Requirements**: Linux host with GPU, or macOS with AMD GPU (Metal)
2. **VM Settings**:
   - Display → "Accelerate 3D graphics" ✓
   - Display → "Use host GPU" ✓
   - Memory: 8GB+ (4GB minimum)
   - CPUs: 4+ cores
3. **Inside VM**:
   ```bash
   # AMD
   sudo pacman -S mesa vulkan-radeon
   # NVIDIA
   sudo pacman -S nvidia nvidia-utils
   ```
4. **Verify**:
   ```bash
   glxinfo | grep "OpenGL renderer"
   ollama run llama3.1  # should use GPU
   ```

## VirtualBox 7+

1. **Host**: Linux with IOMMU enabled
2. **VM Settings**: Enable 3D Acceleration, 128MB video memory
3. **GPU Passthrough**:
   ```bash
   VBoxManage modifyvm "ash" --gpupassthrough on
   ```

## Parallels Desktop 18+ (macOS)

- **Apple Silicon**: Metal acceleration works automatically
- **Intel Mac**: Hardware → Graphics → "Passthrough"

## QEMU/KVM (Linux)

### Prerequisites
```bash
# IOMMU in kernel cmdline, VFIO modules, bind GPU to vfio-pci
```

### VM Command
```bash
qemu-system-x86_64 \
  -enable-kvm -cpu host -m 16G -smp 8 \
  -drive file=ash-2025.01.15.iso,media=cdrom,readonly=on \
  -drive file=ash-disk.qcow2,format=qcow2 \
  -boot d -display gtk,gl=on \
  -device vfio-pci,host=XX:XX.X,multifunction=on \
  -device virtio-gpu-pci
```

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `llama.cpp` falls back to CPU | Install drivers; verify `nvidia-smi` / `rocm-smi` |
| VM hangs on boot with GPU | Add `video=efifb:off` to kernel cmdline |
| Metal not working (macOS) | Parallels 19+ required |
| "No GPU found" in Ollama | `OLLAMA_DEBUG=1 ollama run llama3.1` |

## Model Performance Expectations

| GPU | llama3.1:8b (4-bit) | codellama:13b (4-bit) |
|-----|---------------------|----------------------|
| RTX 4090 (24GB) | ~80 tok/s | ~50 tok/s |
| M3 Max (48GB) | ~55 tok/s | ~35 tok/s |
| RX 7900 XTX (24GB) | ~60 tok/s | ~40 tok/s |
