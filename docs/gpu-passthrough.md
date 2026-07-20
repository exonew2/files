# GPU in VMware

## VMware Display Settings

In VMware Workstation / Fusion:

- VM Settings → Display → **"Accelerate 3D graphics"** ✓
- Allocate at least 4 GB video memory
- Set number of CPU cores to 4+

## VMX Workaround (Hyprland Stability)

Hyprland on VMware requires a display workaround. Add to the VM's `.vmx` file on the **host**:

```
mks.enableVulkanRenderer = "FALSE"
svga.disableFIFO = "TRUE"
```

`mks.enableVulkanRenderer = "FALSE"` disables VMware's Vulkan renderer, which causes tearing, black boxes, and freezes in Hyprland/Wayland. Falls back to the SVGA GPU.

`svga.disableFIFO = "TRUE"` prevents rendering artifacts.

**Status**: Requires host-side action — edit `.vmx` on the Windows/macOS host. Reboot VM after editing.

## Ollama GPU Detection

Ollama auto-detects available GPU acceleration (NVIDIA CUDA, AMD ROCm, Apple Metal). No manual configuration needed.

## Model Considerations

`nomic-embed-text` is lightweight and runs adequately on CPU. GPU acceleration provides modest speedup for batch embedding but is not required.

## Verification

```bash
# Check Ollama version
curl http://localhost:11434/api/version

# Benchmark embedding speed
time curl -X POST http://localhost:11434/api/embeddings \
  -d '{"model":"nomic-embed-text","prompt":"benchmark test"}'
```

If Ollama does not detect your GPU, check:
- VMware 3D acceleration is enabled in VM settings
- VMX workaround lines are not blocking Vulkan (comment them out temporarily)
- `nvidia-smi` or `rocm-smi` shows your GPU inside the VM
