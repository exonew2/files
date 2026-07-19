# Security Policy

## Reporting a Vulnerability

**Do not file public issues for security vulnerabilities.**

Email: **security@ash.sh**

Include:
- Description of the vulnerability
- Steps to reproduce
- Affected versions
- Potential impact
- Suggested fix (if any)

We respond within 48 hours. Critical vulnerabilities get a patch release within 7 days.

## Scope

In scope:
- ISO build process (supply chain)
- First-boot scripts (privilege escalation)
- Guest agent integrations (VM escape)
- Firewall rules (network isolation)
- Snapshot/rollback mechanism (data integrity)
- Signature verification (supply chain)
- AppArmor profiles (AI model sandboxing)
- Kernel hardening parameters
- Pacman signature verification

Out of scope:
- Upstream Arch Linux packages (report to Arch)
- Upstream AI tools (Ollama, llama.cpp, Qdrant — report to their projects)
- Hypervisor vulnerabilities (report to VMware/Oracle/Parallels/QEMU)
- Hardware vulnerabilities (Spectre, Meltdown, etc.)

## Supply Chain Security

Every release provides:
1. **SHA256** — Basic integrity
2. **minisign** — Ed25519 signatures, fast offline verification
3. **cosign (keyless)** — Sigstore transparency log, OIDC identity (bundle + detached signature)
4. **SLSA Level 3 Provenance** — Build attestation via GitHub Actions
5. **GitHub Attestation** — Signed attestation via `actions/attest-build-provenance`

Verify **all** before booting.

## Hardening Measures

### Kernel Hardening
- **Lockdown mode**: `integrity` (restricts loading unsigned modules, debugfs, kexec)
- **BPF hardening**: `bpf_jit_harden=1`, `kernel.unprivileged_bpf_disabled=1`
- **ASLR**: Full randomization with `kernel.randomize_va_space=2`
- **Memory protections**: `slab_nomerge`, `init_on_alloc=1`, `init_on_free=1`, `page_alloc.shuffle=1`
- **CPU mitigations**: Spectre v2, SSBD, KVM NX huge pages, KPTI
- **IOMMU**: Strict DMA isolation, forced IOMMU

### Firewall (nftables)
- Default-deny input policy
- Rate-limited SSH (2 connections per 30s per source IP)
- Port scan detection (null, Xmas, SYN/FIN scans blocked)
- Anti-spoofing rules (martian addresses, bogon filtering)
- Connection tracking for established connections
- VM network sets with auto-discovery
- Logged drops (3/minute rate-limited)

### SSH Hardening
- No root login, no password auth, key-only
- Ed25519 and RSA host keys only (no ECDSA/DSA)
- Modern KEX: `sntrup761x25519-sha512@openssh.com`, Curve25519, DH group exchange
- AEAD ciphers: ChaCha20-Poly1305, AES-GCM
- ETM MACs only
- Rate-limited via nftables
- Max auth tries: 3, Max sessions: 4, Login grace: 30s

### User Security
- `umask 027` system-wide via `/etc/bash.bashrc` and `/etc/skel`
- Sudo timestamp timeout: 5 minutes
- No passwordless sudo persistence
- Secure bash defaults (safe aliases, history controls, PATH safety)

### Package Security
- Pacman signature verification: `Required` level for all packages
- Pre-transaction signature verification hook
- Weekly Arch Linux Security Advisory monitoring
- `arch-audit` available for manual scanning

### AppArmor (AI Sandboxing)
- **Ollama**: Restricted to model directories, GPU devices, denies host system access
- **Qdrant**: Restricted to data directory, network access for gRPC/HTTP only
- Profiles enforced at boot via `iso-apparmor-enforce.service`

## Threat Model

| Threat | Mitigation |
|--------|------------|
| Malicious ISO on mirror | minisign + cosign + SLSA verification |
| Compromised build runner | SLSA L3 provenance, reproducible builds |
| VM escape via guest agent | Minimal agents, seccomp, no host fs access |
| AI model supply chain | Models pulled from Ollama library only, user consent |
| Persistent compromise | Btrfs snapshots + rollback, Qdrant excluded from snaps |
| SSH brute force | nftables rate limiting, key-only auth, fail2ban |
| AI model sandbox escape | AppArmor profiles, no raw network, no proc access |
| Kernel exploit | Lockdown mode, BPF hardening, ASLR, KPTI |

## Security Updates

- Weekly auto-update timer (opt-in) creates pre-snapshot
- Kernel held (`IgnorePkg = linux linux-headers linux-firmware`)
- Security-only updates via `pacman -Syu --ignore=linux*`
- Weekly Arch Linux Security Advisory monitoring
- Emergency releases for critical CVEs within 24h

## Responsible Disclosure Timeline

| Severity | Response | Patch Release |
|----------|----------|---------------|
| Critical (CVSS 9-10) | 24 hours | 7 days |
| High (CVSS 7-8.9) | 48 hours | 14 days |
| Medium (CVSS 4-6.9) | 1 week | 30 days |
| Low (CVSS 0-3.9) | 2 weeks | Next scheduled |

## Hall of Fame

Security researchers who responsibly disclosed:
- *(awaiting first submission)*
