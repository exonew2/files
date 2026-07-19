# GPU Passthrough Guide

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

1. **Host**: Linux with IOMMU enabled (kernel: `intel_iommu=on` or `amd_iommu=on`)
2. **VM Settings**:
   - System → Processor → Enable PAE/NX ✓
   - Display → Video Memory: 128MB ✓
   - Display → 3D Acceleration ✓
3. **GPU Passthrough**:
   ```bash
   VBoxManage modifyvm "ash" --gpupassthrough on
   VBoxManage modifyvm "ash" --gpuuuid <host-gpu-uuid>
   ```
4. **Inside VM**: Same driver installation as VMware

## Parallels Desktop 18+ (macOS)

1. **Apple Silicon (M1/M2/M3)**:
   - Hardware → Graphics → "Auto" ✓
   - Metal acceleration works automatically
   - `ollama run llama3.1` uses Neural Engine + GPU
2. **Intel Mac**:
   - Hardware → Graphics → "Passthrough" ✓
   - Requires AMD GPU (eGPU supported)

## QEMU/KVM (Linux)

### Prerequisites
```bash
# 1. IOMMU in kernel cmdline
# /etc/default/grub: GRUB_CMDLINE_LINUX_DEFAULT="... intel_iommu=on iommu=pt"
sudo grub-mkconfig -o /boot/grub/grub.cfg

# 2. VFIO modules
echo "vfio" >> /etc/modules
echo "vfio_iommu_type1" >> /etc/modules
echo "vfio_pci" >> /etc/modules
echo "vfio_virqfd" >> /etc/modules

# 3. Bind GPU to vfio-pci
# Find GPU: lspci -nn | grep -i nvidia
# /etc/modprobe.d/vfio.conf: options vfio-pci ids=10de:xxxx,10de:xxxx
```

### VM Command
```bash
qemu-system-x86_64 \
  -enable-kvm -cpu host -m 16G -smp 8 \
  -drive file=ash-2025.01.15.iso,media=cdrom,readonly=on \
  -drive file=ash-disk.qcow2,format=qcow2 \
  -boot d -display gtk,gl=on \
  -device virtio-net-pci,netdev=net0 \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -device vfio-pci,host=XX:XX.X,multifunction=on \
  -device vfio-pci,host=XX:XX.X \
  -device virtio-gpu-pci
```

### Verify in VM
```bash
lspci -nn | grep -i nvidia
nvidia-smi
ollama run llama3.1  # should show GPU in logs
```

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `llama.cpp` falls back to CPU | Check `nvidia-smi` / `rocm-smi` in VM; verify driver install |
| VM hangs on boot with GPU | Add `video=efifb:off` to kernel cmdline; try `-device vfio-pci,host=...,x-igd-opregion=on` |
| Metal not working (macOS) | Parallels 19+ required; restart Parallels Desktop |
| "No GPU found" in Ollama | `OLLAMA_DEBUG=1 ollama run llama3.1` to see detection logs |

## Model Performance Expectations

| GPU | llama3.1:8b (4-bit) | codellama:13b (4-bit) |
|-----|---------------------|----------------------|
| RTX 3080 (10GB) | ~50 tok/s | ~30 tok/s |
| RTX 4090 (24GB) | ~80 tok/s | ~50 tok/s |
| M2 Max (32GB) | ~40 tok/s | ~25 tok/s |
| M3 Max (48GB) | ~55 tok/s | ~35 tok/s |
| RX 7900 XTX (24GB) | ~60 tok/s | ~40 tok/s |