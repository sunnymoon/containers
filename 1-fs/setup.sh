#!/usr/bin/env bash
# =============================================================================
# Step 1 — Filesystem Isolation  |  SETUP
# Downloads Alpine Linux minirootfs and extracts it as our "container root"
# =============================================================================
set -euo pipefail

ALPINE_VERSION="3.19.1"
ALPINE_ARCH="x86_64"
TARBALL="alpine-minirootfs-${ALPINE_VERSION}-${ALPINE_ARCH}.tar.gz"
ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/${ALPINE_ARCH}/${TARBALL}"
ROOTFS_DIR="$(dirname "$0")/rootfs"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       Step 1 — Filesystem Isolation: SETUP                  ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo

if [[ -d "$ROOTFS_DIR/bin" ]]; then
    echo "✅  rootfs/ already exists — skipping download."
    echo "    Delete 1-fs/rootfs/ and re-run to start fresh."
    exit 0
fi

echo "📥  Downloading Alpine Linux ${ALPINE_VERSION} minirootfs..."
curl -# -L -o "/tmp/${TARBALL}" "${ALPINE_URL}"

echo
echo "📦  Extracting into rootfs/ ..."
mkdir -p "$ROOTFS_DIR"
tar -xzf "/tmp/${TARBALL}" -C "$ROOTFS_DIR"

echo
echo "✅  Done! rootfs/ contains:"
ls "$ROOTFS_DIR"
echo
echo "👉  Now run:  ./demo.sh"
