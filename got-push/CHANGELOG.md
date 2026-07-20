# Changelog

All notable changes to ash-iso are documented here.

## [2.0.0] — 2026-07-20

### Added
- Pure-bash LSFS launcher hook (zero Python dependencies)
- nomic-embed-text embedding model (768-dim) via Ollama
- Qdrant standalone binary installer (no Docker required)
- VMware-specific fixes (VMX workaround, clipboard, display resolution)
- Auto-login and auto-start on boot
- ultimate-fix-v2.sh one-shot repair and deploy script

### Changed
- All documentation rewritten to match actual project state

### Removed
- ISO download references (project is a VM deploy, not an ISO)
- ash-linux/ash naming — now canonical at github.com/exonew2/files
- llama.cpp references (not part of the default stack)
- GNOME desktop references (minimal Arch deployment)
- Btrfs snapshot infrastructure (not used)

## [1.x] — 2026-07-19

### Added
- Initial deployment scripts for Arch Linux VM
- Ollama integration
- Qdrant vector store setup
- Basic VMware guest configuration
- LSFS prototype
