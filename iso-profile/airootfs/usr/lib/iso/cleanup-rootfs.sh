#!/usr/bin/bash
# /usr/lib/iso/cleanup-rootfs.sh — Strip rootfs to reduce ISO size
# Runs at build time (in chroot) and optionally at first boot for VM compaction.
# WARNING: This removes files permanently. Only run in ISO build chroot.
set -euo pipefail

log() { logger -t cleanup-rootfs "$*"; }

if [[ ! -f /.dockerenv ]] && [[ ! -f /run/iso-build ]]; then
    log "WARNING: Not in build chroot — skipping destructive cleanup"
    exit 1
fi

log "Starting rootfs cleanup..."

# 1. Remove package cache
pacman -Scc --noconfirm 2>/dev/null || true

# 2. Remove locale files other than en_US
find /usr/share/locale -mindepth 1 -maxdepth 1 ! -name 'en*' ! -name 'locale.alias' ! -name 'C.UTF-8' -prune -exec rm -rf {} + 2>/dev/null || true
find /usr/share/i18n/locales -type f ! -name 'en_US*' ! -name 'POSIX' ! -name 'C' -delete 2>/dev/null || true
find /usr/share/i18n/charmaps -type f ! -name 'UTF-8*' ! -name 'ANSI_X3.4-1968*' ! -name 'ISO-8859-1*' -delete 2>/dev/null || true

# 3. Remove man pages other than English
find /usr/share/man -mindepth 1 -maxdepth 1 ! -name 'en*' ! -name 'man*' -prune -exec rm -rf {} + 2>/dev/null || true
# Remove man pages entirely to save space (docs can be fetched online)
rm -rf /usr/share/man/en* /usr/share/help/* 2>/dev/null || true

# 4. Remove info pages
rm -rf /usr/share/info/* 2>/dev/null || true

# 5. Remove documentation
rm -rf /usr/share/doc/* 2>/dev/null || true
rm -rf /usr/share/gtk-doc/* 2>/dev/null || true

# 6. Remove systemd journal logs
rm -rf /var/log/journal/* 2>/dev/null || true
rm -f /var/log/*.log 2>/dev/null || true

# 7. Remove temporary files
rm -rf /tmp/* 2>/dev/null || true
rm -rf /var/tmp/* 2>/dev/null || true

# 8. Remove pacman cache and sync DBs (ships in ISO, rebuilt on update)
rm -rf /var/cache/pacman/pkg/* 2>/dev/null || true
rm -rf /var/lib/pacman/sync/* 2>/dev/null || true

# 9. Remove unnecessary Python bytecache and tests
find /usr/lib/python* -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true

# 10. Remove unnecessary kernel headers from ISO
rm -rf /usr/src/* 2>/dev/null || true

# 11. Clean empty directories
find /etc -type d -empty -delete 2>/dev/null || true
find /var -type d -empty -delete 2>/dev/null || true

# 12. Zero free space for better squashfs compression
dd if=/dev/zero of=/zero.fill bs=1M 2>/dev/null || true
rm -f /zero.fill

log "Rootfs cleanup complete"
