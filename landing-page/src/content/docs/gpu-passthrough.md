---
title: GPU in VMware
description: VMware display workaround, VMX edits, and Ollama GPU detection for Hyprland.
order: 3
---

## VMware 3D Acceleration

In VMware Fusion / Workstation VM settings:

1. VM → Settings → Display
2. **Enable Accelerate 3D graphics**
3. Allocate at least **4 GB** video memory

## VMX Workaround for Hyprland

Hyprland requires explicit GPU configuration. Edit the `.vmx` file:

```
mks.enable3d = "TRUE"
svga.guestBackedPrimary = "TRUE"
svga.vramSize = "4294967296"
```

**Needs host action:** On Windows hosts, add `mks.enableGL=TRUE` to the VMX. On macOS Fusion, Metal acceleration is automatic with VM 13+.

## Display Fix

**Needs host action:** The VMX must include a display workaround for proper HiDPI / multi-monitor behavior with Hyprland. Add to `.vmx`:

```
gui.fitguestusingnativedisplayresolution = "TRUE"
```

## Ollama GPU Detection

Ollama auto-detects the GPU. Verify inside the VM:

```bash
# Check if GPU renderer is available
glxinfo -B | grep -i renderer

# Ollama detects GPU backend
journalctl -u ollama --no-pager | grep -i gpu
```

**Note:** VMware provides GPU compute via SVGA 3D acceleration, not true PCIe passthrough. For bare-metal GPU performance, use QEMU/KVM with VFIO.
