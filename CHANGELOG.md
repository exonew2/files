# Changelog

All notable changes to ash will be documented in this file.

## [Unreleased]

### Added
- Initial release of ash ISO
- Btrfs + Snapper instant rollback
- Ollama + llama.cpp + Qdrant pre-installed
- GPU passthrough for VMware, VirtualBox, Parallels, QEMU
- 4 verification mechanisms: SHA256, minisign, cosign, SLSA
- Multi-format: ISO, OVA (VMware/VirtualBox), PVM (Parallels), QCOW2, VHDX, Vagrant, Cloud images
- Clinical Clean landing page with 4 CSS-only animations

## [2025.01.15] - 2025-01-15

### Added
- First stable release
- Arch Linux base with Linux 6.12 LTS
- GNOME on Xorg (Wayland disabled for VM compatibility)
- Ollama with phi3:mini baked in, llama3.1:8b auto-pulled
- llama.cpp with GGUF support
- Qdrant vector database (persisted, excluded from snapshots)
- nftables firewall with VM subnet allowlist
- Btrfs on LUKS2 (password: "ai") with Snapper timeline
- GRUB-Btrfs for snapshot boot menu entries
- SSH socket-activated, key-only auth
- VM guest agents: VMware Tools, VirtualBox Guest Additions, QEMU GA, SPICE
- Auto time/keyboard detection from hypervisor
- Config drive / USB / GuestInfo / QEMU fw_cfg customization
- Weekly auto-update timer with pre/post snapshots
- Debug log collection and GitHub issue reporting
- One-click VM uninstall from desktop

### Security
- minisign Ed25519 signatures on all artifacts
- cosign keyless signatures with Sigstore transparency log
- SLSA Level 3 build provenance
- Reproducible builds via pinned Arch package versions
- Kernel lockdown mode enabled
- AppArmor profiles for Ollama, Qdrant, guest agents

---

## Versioning

ash uses **CalVer**: `YYYY.MM.MICRO`

- `YYYY` — Year
- `MM` — Month (01-12)
- `MICRO` — Patch number within month

Example: `2025.01.3` = January 2025, 3rd release

Git tags: `v2025.01.3`

## Release Schedule

- **Monthly**: Feature releases (new AI models, hypervisor support, UI improvements)
- **As needed**: Security patches (kernel CVEs, critical vulnerabilities)
- **Weekly**: Auto-update timer creates snapshots for users who opt in

## Support Policy

| Release | Support Until | Notes |
|---------|---------------|-------|
| 2025.01.x | 2025-07-01 | 6 months |
| 2025.02.x | 2025-08-01 | 6 months |
| ... | ... | ... |

LTS releases (every 6 months): 12 months support