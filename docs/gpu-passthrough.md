# GPU Passthrough — VMware

## VMware Display Settings

In VMware Fusion / Workstation:

- VM Settings → Display → **"Accelerate 3D graphics"** ✓
- Allocate at least 4 GB video memory (more if running larger models)
- Set number of CPU cores to 4+

## VMX Workaround (Hyprland Stability)

If Hyprland experiences tearing, freezing, or crashes on Wayland, add these lines to the `.vmx` file:

```
mks.enableVulkanRenderer = "FALSE"
svga.disableFIFO = "TRUE"
```

These disable the Vulkan renderer and FIFO buffer that sometimes conflict with Hyprland. Reboot the VM after editing `.vmx`.

## Ollama GPU Detection

Ollama auto-detects available GPU acceleration:

- **NVIDIA (CUDA)** — detected automatically if `nvidia-smi` works
- **AMD (ROCm)** — detected on supported GPUs
- **Apple Metal** — used on macOS hosts (VMware Fusion)

No manual configuration is needed. Verify with:

```bash
curl http://localhost:11434/api/tags
ollama run nomic-embed-text 2>&1 | grep -i gpu
```

## Model Considerations

| Model | Dimensions | GPU Benefit |
|-------|------------|-------------|
| nomic-embed-text | 768 | Minor (runs well on CPU) |

`nomic-embed-text` is lightweight and runs adequately on CPU. GPU acceleration provides a modest speedup for batch embedding but is not required.

## Verification

```bash
# Check if Ollama sees GPU
curl http://localhost:11434/api/version

# Benchmark embedding speed
time curl -X POST http://localhost:11434/api/embeddings \
  -d '{"model":"nomic-embed-text","prompt":"benchmark test"}'
```

If Ollama does not detect your GPU, check:
- VMware 3D acceleration is enabled in VM settings
- VMX workaround lines are not blocking Vulkan (comment them out temporarily)
- `nvidia-smi` or `rocm-smi` shows your GPU inside the VM
