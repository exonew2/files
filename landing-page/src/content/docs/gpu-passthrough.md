---
title: GPU in VMware
description: Configure GPU acceleration in VMware Fusion and Workstation for the ash-iso VM.
order: 3
---

## VMware Fusion (macOS)

1. Select the VM → Settings → Display
2. Check **Accelerate 3D graphics**
3. Check **Use host GPU** (Metal acceleration)
4. Set at least **4 GB** video memory
5. Apply and reboot the VM

## VMware Workstation (Linux/Windows)

1. VM → Settings → Display
2. Check **Accelerate 3D graphics**
3. Select **Use host settings for monitors**
4. Set **Graphics memory** to 4 GB or higher
5. Apply and reboot

## Verify Inside VM

```bash
# Check if GPU renderer is available
glxinfo -B | grep -i renderer

# Ollama GPU detection
ollama run nomic-embed-text
# Check logs for GPU device
journalctl -u ollama --no-pager | grep -i gpu
```

## Notes

- VMware does not support true PCIe passthrough — 3D acceleration provides GPU compute via the VMware SVGA driver
- For serious GPU workloads, use a Linux host with QEMU/KVM VFIO passthrough instead
- On Apple Silicon Macs, Metal acceleration is automatic in VMware Fusion 13+
