# Security — ash-iso VM Deployment

## VM Isolation

The ash-iso project deploys an Arch Linux virtual machine. All security is built on VM boundaries — the guest is contained by VMware, which prevents escape, host filesystem access, and raw device access by default. No additional hardening profiles are applied inside the VM beyond standard Arch Linux defaults.

## Network Exposure

Ollama listens on `127.0.0.1:11434`. Qdrant listens on `127.0.0.1:6333` and `127.0.0.1:6334`. Neither service is exposed beyond localhost inside the VM. No inbound ports are opened in the guest firewall. The VM operates behind VMware's NAT or host-only networking by default — no services are reachable from the host network or the internet.

## Attack Surface

- **Zero open ports** on guest startup
- **No SSH server** enabled by default
- **No root password** exposed — `sudo` is the sole escalation path
- **VM boundary** is the security perimeter, not guest-level AppArmor or seccomp

## Updates

Security updates come via `git pull` from the upstream repository. The deployment script (`ultimate-fix-v2.sh`) is the single source of truth — re-running it reapplies the latest configuration and patches. Model and binary updates (Ollama, Qdrant) are pulled from their respective official sources.

## Reporting

Report security concerns by opening a GitHub issue at https://github.com/exonew2/files/issues.
