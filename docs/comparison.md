# Comparison: ash vs Alternatives

## Quick Comparison

| Feature | **ash ISO** | Gitpod / Codespaces | Dev Containers | Manual Arch VM |
|---------|-------------|---------------------|----------------|----------------|
| **Local / Offline** | ✅ 100% | ❌ Cloud only | ✅ Local | ✅ Local |
| **Zero Config** | ✅ Boot → Code | ⚠️ Config needed | ⚠️ Dockerfile | ❌ Hours |
| **GPU / Local AI** | ✅ Native passthrough | ❌ No local GPU | ✅ Via Docker | ⚠️ Manual |
| **Arch + GNOME** | ✅ Pre-configured | ❌ Ubuntu base | ❌ DIY | ⚠️ Manual |
| **AI Tools Ready** | ✅ Ollama, llama.cpp, Qdrant, Continue | ❌ Manual | ❌ Manual | ❌ Manual |
| **Instant Rollback** | ✅ Btrfs + Snapper | ❌ N/A | ❌ N/A | ❌ Manual |
| **Supply Chain Verify** | ✅ SHA256 + minisign + cosign + SLSA | ❌ Opaque | ⚠️ Docker trust | ✅ Manual |
| **Boot Time** | **~45s** | 60-120s (cloud start) | 30-60s (build) | Hours |
| **Cost** | **Free** | $10-50/mo | Free (Docker) | Free (time) |
| **Persistent Memory** | ✅ Qdrant vectors | ❌ Session only | ❌ Container only | ❌ Manual |

## Detailed Comparison

### vs GitHub Codespaces / Gitpod

| Aspect | ash | Codespaces / Gitpod |
|--------|-----|---------------------|
| **Data Privacy** | 100% local | Code leaves your machine |
| **Internet Required** | No (after download) | Yes, always |
| **Latency** | Zero (local) | Network dependent |
| **GPU Access** | Native passthrough | Limited/None |
| **Model Privacy** | Local only | Sent to cloud |
| **Cost** | Free (hardware only) | $10-50/month/seat |
| **Customization** | Full Arch control | Constrained |
| **Offline Work** | ✅ Full | ❌ Impossible |

### vs Dev Containers (VS Code / Docker)

| Aspect | ash | Dev Containers |
|--------|-----|----------------|
| **Setup Time** | 45s boot | 30-60s build + config |
| **Config** | None needed | Dockerfile + devcontainer.json |
| **Rebuild on Change** | No (live system) | Yes (rebuild container) |
| **GPU** | Native | Via Docker (extra config) |
| **Snapshots** | Btrfs instant | Docker commit (slow) |
| **Host Integration** | VM-level isolation | Process-level |
| **AI Tools** | Pre-installed | Manual install each rebuild |

### vs Manual Arch VM

| Aspect | ash | Manual Arch |
|--------|-----|-------------|
| **Install Time** | 45s (boot ISO) | 2-4 hours |
| **Config Files** | Pre-done | Manual |
| **AI Stack** | Pre-installed | Manual each tool |
| **Desktop** | GNOME + Hyprland ready | Manual |
| **Snapshots** | Snapper + GRUB-Btrfs | Manual Btrfs/LVM |
| **Guest Agents** | All enabled | Manual per hypervisor |
| **GPU Passthrough** | Works OOTB | Manual VFIO/IOMMU |
| **Updates** | Auto + snapshots | Manual |

## When to Use Each

| Use Case | Recommended |
|----------|-------------|
| **AI coding, local LLMs, privacy** | **ash ISO** |
| **Team collaboration, cloud CI/CD** | Codespaces / Gitpod |
| **Consistent dev env across team** | Dev Containers |
| **Learning Arch, full control** | Manual Arch VM |
| **Ephemeral experiments** | **ash ISO** (destroy after) |
| **Production-like staging** | Dev Containers / Codespaces |

## The ash Advantage

> **Download → Boot → Code. No config. No cloud. No `curl \| sh`. No rebuilds. Instant snapshots. Native GPU. Your hardware. Your models. Your rules.**

### Unique ash Features

1. **Btrfs Snapshots + GRUB-Btrfs** — Rollback from boot menu
2. **Qdrant Vector Memory** — AI remembers across sessions
3. **Dependency Firewall** — Blocks malicious packages (npm/pip/cargo)
4. **eBPF Audit Trail** — Every syscall logged
4. **Model Router** — Auto-selects best model per task
5. **Multi-Hypervisor** — One ISO, works everywhere
6. **Supply Chain Security** — 4-way verification
7. **Zero Config** — Timezone, keyboard, user, SSH, agents all auto