# Contributing to ash

Thanks for contributing! Here's how to get started.

## Development Setup

```bash
git clone https://github.com/ash-linux/ash
cd ash

# Build ISO locally (requires Arch Linux or Arch-based host)
./scripts/build-iso.sh 2025.01.1-dev

# Test boot in QEMU
qemu-system-x86_64 -enable-kvm -cpu host -m 4G -smp 4 \
  -drive file=out/ash-2025.01.1-dev.iso,media=cdrom,readonly=on \
  -boot d -display gtk -serial stdio

# Run tests
./scripts/test-iso.sh out/ash-2025.01.1-dev.iso
```

## Project Structure

```
ash-iso/
├── .github/workflows/       # CI/CD pipelines
├── iso-profile/             # mkarchiso profile (the ISO build)
│   └── airootfs/            # Root filesystem overlay
├── packer/                  # Packer templates for VM formats
├── landing-page/            # Astro static site (ash.sh)
├── scripts/                 # Build, sign, distribute, verify
└── docs/                    # Documentation
```

## Guidelines

1. **Fork → Branch → PR** — One feature per PR
2. **Test before PR** — Run `./scripts/test-iso.sh` on your build
3. **Follow Arch conventions** — `pacman` packages, systemd units, `/etc` layout
4. **Update docs** — If user-facing, update `/docs` and landing page
5. **Sign commits** — `git commit -S` (GPG signed)

## Areas for Contribution

- [ ] Additional AI models in default pull list
- [ ] More hypervisor guest agent integrations
- [ ] ARM64 / Apple Silicon support (UTM native)
- [ ] Accessibility improvements (Orca, high contrast)
- [ ] Language packs beyond en_US
- [ ] Documentation translations
- [ ] CI/CD pipeline improvements
- [ ] Test coverage expansion

## Security

See [SECURITY.md](SECURITY.md) for vulnerability reporting.

## License

By contributing, you agree your contributions are licensed under MIT.