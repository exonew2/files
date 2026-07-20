# Comparison — ash-iso vs Other Approaches

## Quick Comparison

| Feature | **ash-iso on Arch VM** | Plain Arch Setup | Ubuntu Desktop | ISO-Based AI OS Projects |
|---------|------------------------|------------------|----------------|--------------------------|
| **Setup Time** | 1 min (one-liner) | 2–4 hours | 30 min install + manual config | 45s boot |
| **Semantic Search** | ✅ Built-in (LSFS) | ❌ Manual | ❌ Manual | ⚠️ Often absent |
| **Vector Memory** | ✅ Qdrant standalone | ❌ None | ❌ None | ⚠️ Varies |
| **Pure-Bash Launcher** | ✅ curl + wofi only | ❌ None | ❌ None | ❌ Python/JS stack |
| **One-Liner Deploy** | ✅ `curl | sudo bash` | ❌ N/A | ❌ N/A | ❌ ISO download |
| **Local / Offline** | ✅ 100% | ✅ 100% | ✅ 100% | ✅ 100% |
| **VMware Optimized** | ⚠️ VMX fix documented, clipboard needs host action | ❌ Manual | ❌ Manual | ❌ Generic |
| **Rollback** | ⚠️ Manual backups | ⚠️ Manual backups | ⚠️ Manual snapshots | ✅ Btrfs snapshots |
| **Customization** | ✅ Full Arch control | ✅ Full Arch control | ❌ Constrained | ⚠️ Fixed filesystem |
| **GPU Passthrough** | ⚠️ VMX workaround needed | ⚠️ Manual | ⚠️ Manual | ✅ Pre-configured |

## Detailed Comparison

### vs Plain Arch Linux Setup

| Aspect | ash-iso | Plain Arch |
|--------|---------|------------|
| Install + Config Time | ~1 minute | 2–4 hours |
| Semantic File Search | Pre-configured | Manual (none available) |
| Vector DB | Qdrant binary systemd service | None |
| AI Launcher | Super+Space → wofi → curl → Qdrant | None |
| Hyprland Config | Pre-tuned for VMware | Manual |
| Auto-Login | Configured out of the box | Manual |

### vs Ubuntu Desktop

| Aspect | ash-iso | Ubuntu |
|--------|---------|--------|
| Package Freshness | Arch (rolling) | Ubuntu (fixed release) |
| Semantic Search | Native | None (or GNOME Search) |
| AI Stack Integration | One-command deploy | Manual pip/apt install |
| Wayland Compositor | Hyprland (pre-configured) | GNOME (generic) |
| Storage Overhead | Minimal (scripts only) | 5–10 GB base |

### vs ISO-Based AI OS Projects

| Aspect | ash-iso | ISO-based projects |
|--------|---------|--------------------|
| Deployment | Script on existing Arch | Download + boot ISO |
| Host Modification | No reinstall needed | Destructive (new VM/partition) |
| File System | Your existing setup | Btrfs subvolumes, read-only root |
| Update Model | Re-run deploy script | ISO re-download or A/B updates |
| Snapshot/Rollback | Manual (backup your data) | Built-in (Snapper, Btrfs) |
| Flexibility | Full control of base system | Opinionated defaults |

## When to Use What

| Use Case | Recommendation |
|----------|----------------|
| Already have Arch + Hyprland, want semantic search | **ash-iso** (one-liner) |
| Setting up a new VM for AI-assisted development | Arch install + ash-iso |
| Want zero-config AI OS appliance | ISO-based project |
| Need maximum customization | Plain Arch + cherry-pick ash-iso scripts |
| Ephemeral experiments | ash-iso (scratchable VM) |

## Key Differentiators

- **Semantic search** — bash launcher calls Ollama embeddings API, queries Qdrant. No Python in the search path.
- **nomic-embed-text** — 768-dim, Ollama-native model, small and fast on CPU.
- **Qdrant standalone binary** — no AUR, no Docker, no Python SDK. Static musl binary from GitHub releases.
- **VMware-first** — VMX workaround documented for Hyprland stability, open-vm-tools installed.
- **One-liner deploy** — idempotent, re-runnable. No ISO download, no hypervisor import.

## Limitations

- **Clipboard**: open-vm-tools installed, but host-side `.vmx` edit required for copy/paste
- **Display**: VMX workaround (`mks.enableVulkanRenderer = "FALSE"`) needed for Hyprland stability
- **Index scope**: daemon indexes `~/.config/scripts` by default; other paths must be configured manually
- **No rollback**: no Btrfs snapshots or A/B update mechanism — backup manually
