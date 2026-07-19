# ash

> **A**rch **S**napshot **H**ypervisor — *Code burns bright. Ash remains clean.*

[![License](https://img.shields.io/github/license/ash-linux/ash?style=flat-square)](LICENSE)
[![Build Status](https://img.shields.io/github/actions/workflow/status/ash-linux/ash/build-iso.yml?style=flat-square)](https://github.com/ash-linux/ash/actions)
[![GitHub Release](https://img.shields.io/github/v/release/ash-linux/ash?style=flat-square&label=latest)](https://github.com/ash-linux/ash/releases)
[![Discord](https://img.shields.io/discord/ash?style=flat-square&label=discord)](https://discord.gg/ash)

**Download the ISO. Boot. Code with AI. No install. No config. No `curl | sh`.**

<div align="center">
  <img src="./docs/demo.gif" alt="ash demo" width="600" />
</div>

## Quick Start

```bash
# 1. Download (2.3 GB)
wget https://github.com/ash-linux/ash/releases/latest/download/ash-2025.01.1.iso

# 2. Verify (REQUIRED)
sha256sum -c ash-2025.01.1.iso.sha256
minisign -Vm ash-2025.01.1.iso -P RWQf6LRCGA9i52mlZT2k5B5Y5Q5Y5Q5Y5Q5Y5Q5Y5Q5Y5Q5Y5Q5Y5Q5Y5Q5Y= -x ash-2025.01.1.iso.minisig

# 3. Import & Boot
# VMware: File → New → "Install from disc or image" → Select ISO
# VirtualBox: New → Arch Linux (64-bit) → 8GB RAM → 4 CPU → Storage → Optical Drive → Select ISO
# Parallels: File → New → "Install from DVD or image file" → Select ISO

# 4. Code
# Desktop loads in ~45s. Terminal opens. Run:
ollama run llama3.1
# or
ai-model-selector  # GUI to pull models
```

## Why ash?

| Problem | ash Solution |
|---------|--------------|
| **AI breaks your system** | Btrfs snapshots — instant rollback. `snapper rollback 42` |
| **Malicious packages** | nftables firewall + dependency firewall blocks slopsquatting |
| **No local GPU for AI** | Native GPU passthrough (VMware/VirtualBox/Parallels/QEMU) |
| **Cloud-only AI tools** | 100% offline: Ollama + llama.cpp + Qdrant vector memory |
| **Config hell** | Zero config. Boot ISO → desktop → code. |
| **Supply chain attacks** | SHA256 + minisign + cosign + SLSA Level 3 provenance on every release |

## Features

- **Instant Rollback** — Btrfs + Snapper: hourly, daily, monthly, pre/post `pacman`
- **AI-Ready Desktop** — GNOME on Xorg + Hyprland (alt), Ollama, llama.cpp, Continue, Cody
- **Vector Memory** — Qdrant persists across reboots (excluded from snapshots)
- **Model Router** — `ai-model-selector` GUI pulls models on demand
- **GPU Passthrough** — Works out of the box on VMware, VirtualBox, Parallels, QEMU/KVM
- **Zero Config** — Timezone, keyboard, user, SSH, guest agents — all auto-detected
- **Verifiable** — Every release: SHA256, minisign, cosign (keyless), SLSA provenance
- **Delta Updates** — `btrfs send/receive` + `zsync` for 5-30% bandwidth

## Formats Available

| Format | Use Case | Size |
|--------|----------|------|
| **ISO (Hybrid BIOS/UEFI)** | All hypervisors, USB, bare metal | 2.3 GB |
| **VMware OVA** | VMware Fusion/Workstation/ESXi | 2.5 GB |
| **VirtualBox OVA** | VirtualBox 7+ | 2.5 GB |
| **Parallels PVM** | Parallels Desktop 18+ (macOS) | 2.5 GB |
| **QCOW2** | QEMU/KVM, libvirt, Proxmox | 2.3 GB |
| **VHDX** | Hyper-V | 2.5 GB |
| **Vagrant Box** | `vagrant init ash-linux/ash` | 2.3 GB |
| **AWS AMI / GCP Image / Azure VHD** | Cloud deployments | ~3.5 GB |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      ash ISO (Arch Linux)                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │
│  │   GNOME     │  │  Ollama     │  │  Qdrant     │          │
│  │  (Xorg)     │  │  + Models   │  │  (Vectors)  │          │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘          │
│         │                │                │                  │
│  ┌──────▼────────────────▼────────────────▼──────┐          │
│  │           Btrfs Subvolumes                     │          │
│  │  @  @home  @log  @cache  @qdrant  @snapshots   │          │
│  └────────────────────┬──────────────────────────┘          │
│                       │                                     │
│  ┌────────────────────▼──────────────────────────┐          │
│  │         Linux Namespaces + cgroups v2          │          │
│  │  (PID, Mount, Net, User, UTS, IPC isolation)  │          │
│  └────────────────────────────────────────────────┘          │
└─────────────────────────────────────────────────────────────┘
```

## Verification

Every release is signed with **three independent mechanisms**:

```bash
# 1. SHA256 (basic integrity)
sha256sum -c ash-2025.01.1.iso.sha256

# 2. minisign (Ed25519, fast, offline verification)
minisign -Vm ash-2025.01.1.iso -P RWQf6LRCGA9i52mlZT2k5B5Y5Q5Y5Q5Y5Q5Y5Q5Y5Q5Y5Q5Y5Q5Y5Q5Y= -x ash-2025.01.1.iso.minisig

# 3. cosign (keyless, transparency log, SLSA provenance)
cosign verify-blob \
  --bundle ash-2025.01.1.iso.cosign.bundle \
  --certificate-identity-regexp "https://github.com/ash-linux/ash/.github/workflows/release.yml@refs/tags/v*" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  ash-2025.01.1.iso
```

## Documentation

- [Quick Start](/docs/quickstart.md)
- [GPU Passthrough](/docs/gpu-passthrough.md)
- [Persistence](/docs/persistence.md)
- [Updates](/docs/updates.md)
- [Verification](/docs/verification.md)
- [Comparison](/docs/comparison.md)

## Community

- **GitHub**: [ash-linux/ash](https://github.com/ash-linux/ash) — Issues, PRs, Releases
- **Discord**: [discord.gg/ash](https://discord.gg/ash) — Support, discussion
- **Reddit**: [r/ashlinux](https://reddit.com/r/ashlinux) — Community

## License

MIT — see [LICENSE](LICENSE).

---

**Built for the vibe-coding era.** | [Download Latest](https://github.com/ash-linux/ash/releases/latest) | [Verify](https://ash.sh/verify)