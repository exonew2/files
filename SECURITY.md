# Security

## Current deployment posture
- All services listen on localhost only (127.0.0.1):
  - Ollama: 127.0.0.1:11434
  - Qdrant: 127.0.0.1:6333
- No ports exposed to network
- VM boundary provides isolation from host
- systemd sandboxing for services:
  - qdrant.service: User=qdrant, CPUQuota=50%, MemoryMax=2G
  - lsfs-daemon.service: Nice=19, IOSchedulingClass=idle
- Launcher hook runs as user, no root access

## Known gaps
- No firewall configured inside VM
- No AppArmor/SELinux profiles
- Clipboard requires disabling host isolation (VMX edit)
