#!/usr/bin/bash
# /usr/lib/iso/lsfs-setup.sh — First-boot LSFS setup (v2)

log() { echo "[lsfs] $*"; logger -t iso-lsfs "$*" 2>/dev/null || true; }

log "Setting up LSFS (Semantic Filesystem) v2"

# 1. Install Python dependencies
# fusepy via pip if not bundled
if ! python3 -c "import fuse" 2>/dev/null; then
    pip install --break-system-packages fusepy 2>/dev/null || \
        pip install fusepy 2>/dev/null || \
        log "WARNING: fusepy not installed — LSFS FUSE will not work"
fi

# sentence-transformers + aiohttp for cross-encoder + async
if ! python3 -c "import sentence_transformers" 2>/dev/null; then
    pip install --break-system-packages sentence-transformers aiohttp 2>/dev/null || \
        pip install sentence-transformers aiohttp 2>/dev/null || \
        log "WARNING: sentence-transformers not installed — cross-encoder reranking disabled"
fi

# 2. Install tree-sitter + grammars (Bottleneck 1: Multi-Language Chunking)
pip install --break-system-packages tree-sitter 2>/dev/null || \
    pip install tree-sitter 2>/dev/null || \
    log "WARNING: tree-sitter not installed — falling back to ast chunking"

for TS_GRAMMAR in \
    tree-sitter-python tree-sitter-javascript tree-sitter-typescript \
    tree-sitter-rust tree-sitter-go tree-sitter-c tree-sitter-cpp \
    tree-sitter-java tree-sitter-kotlin tree-sitter-swift tree-sitter-ruby \
    tree-sitter-php tree-sitter-bash tree-sitter-lua tree-sitter-scala \
    tree-sitter-haskell tree-sitter-sql tree-sitter-r tree-sitter-zig \
    tree-sitter-dart tree-sitter-c-sharp tree-sitter-yaml tree-sitter-toml \
    tree-sitter-json tree-sitter-html tree-sitter-css tree-sitter-xml \
    tree-sitter-elixir tree-sitter-clojure tree-sitter-julia \
    tree-sitter-perl tree-sitter-ocaml tree-sitter-erlang \
    tree-sitter-groovy tree-sitter-crystal tree-sitter-nim \
    tree-sitter-hcl tree-sitter-protobuf tree-sitter-vue \
    tree-sitter-svelte; do
    pip install --break-system-packages "$TS_GRAMMAR" 2>/dev/null || true
done

# 3. Install python-magic for MIME-type detection (Bottleneck 4)
pip install --break-system-packages python-magic 2>/dev/null || \
    pip install python-magic 2>/dev/null || \
    log "WARNING: python-magic not installed — MIME skipping disabled"

# 4. Ensure FUSE config allows other users
mkdir -p /etc/fuse.conf.d 2>/dev/null || true

# 5. Create mount point
mkdir -p /mnt/lsfs

# 6. Configure Qdrant Unix Domain Socket
mkdir -p /etc/systemd/system/qdrant.service.d
cat > /etc/systemd/system/qdrant.service.d/uds.conf << 'EOF'
[Service]
ExecStartPre=/bin/rm -f /tmp/lsfs.sock
ExecStart=
ExecStart=/usr/bin/qdrant --socket-path /tmp/lsfs.sock
EOF
systemctl daemon-reload

# 7. Enable LSFS mount unit
systemctl enable mnt-lsfs.mount 2>/dev/null || log "WARNING: mnt-lsfs.mount not found"

# 8. Pull multilingual embedding model (Bottleneck 8)
ollama pull nomic-embed-text 2>/dev/null || \
    log "WARNING: nomic-embed-text model pull failed — run: ollama pull nomic-embed-text"

log "LSFS setup complete — mount with: systemctl start mnt-lsfs.mount"
