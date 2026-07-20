# Ash-ISO — Agentic Swarm Habitat OS

> Arch Linux VM with semantic file search, vector memory, and AI-native desktop launcher. Deployed on VMware.

## One-Shot Deploy

```bash
# Requires git clone (repo is private — PAT or SSH key required)
git clone https://github.com/exonew2/files.git && cd files
sudo bash scripts/ultimate-fix-v2.sh
```

Idempotent. Safe to re-run. Installs everything on an existing Arch Linux system.

## What Actually Works

| Feature | Status | Notes |
|---------|--------|-------|
| Hyprland + Catppuccin Mocha | ✅ Working | Wayland compositor, auto-login, auto-start |
| Super+Space launcher hook | ✅ Working | Pure bash (~50 lines), calls Ollama + Qdrant via curl |
| Semantic file search via Ollama | ✅ Working | `nomic-embed-text` model, 768-dim vectors, pinned in VRAM |
| Qdrant standalone binary | ✅ Working | systemd service, no Docker, no AUR |
| LSFS indexing daemon | ✅ Working | User systemd service, watches files, indexes into Qdrant |
| Auto-login → Hyprland | ✅ Working | agetty autologin + .bash_profile |
| Auto-start all services | ✅ Working | Qdrant, Ollama, LSFS, VMware tools at boot |
| Graceful fallback (fd/find) | ✅ Working | Time queries work when Qdrant is down |
| VMware clipboard | ⚠️ Needs host action | open-vm-tools installed, but requires .vmx edit on Windows host |
| Hyprland on VMware | ⚠️ Needs host action | VMX workaround required for Vulkan renderer |

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Hyprland (Wayland Compositor)                          │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Super+Space → lsfs_launcher_hook.sh (bash)      │   │
│  │       │                                           │   │
│  │       ├──→ curl POST /api/embeddings (Ollama)     │   │
│  │       │      127.0.0.1:11434  nomic-embed-text    │   │
│  │       │                                           │   │
│  │       └──→ curl POST /collections/.../search      │   │
│  │              127.0.0.1:6333  Qdrant               │   │
│  │                                                    │   │
│  │         Results → woofi → hyprctl dispatch exec    │   │
│  └──────────────────────────────────────────────────┘   │
│                                                          │
│  Services (systemd):                                     │
│    ollama.service      → 127.0.0.1:11434                 │
│    qdrant.service      → 127.0.0.1:6333                  │
│    lsfs-daemon.service → user service, indexes files     │
│    vmtoolsd.service    → VMware guest services           │
└─────────────────────────────────────────────────────────┘
```

## Current Status

`#deploy` `#working` `#needs-vmx-edit` `#private-repo`

## Quick Links

| File | Purpose |
|------|---------|
| `scripts/ultimate-fix-v2.sh` | One-shot deploy (813 lines, self-contained) |
| `scripts/lsfs_launcher_hook.sh` | Pure-bash search hook (~50 lines) |
| `docs/quickstart.md` | Deploy on existing Arch Linux |
| `docs/agentic-swarm-setup.md` | Desktop integration guide |
