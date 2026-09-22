#!/usr/bin/env bash
# Build the PB2 CAN Carrier Debian/Linux image from pinned sources.
#
# Status: not yet implemented. This script intentionally fails fast until
# manifests/sources.lock is filled in and the real build steps (clone
# pinned sources, apply patches/kernel/*, build kernel + U-Boot, compile
# dts/*.dtso, assemble the Debian rootfs, write checksums to release/) are
# written in, per work order §10.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if grep -q 'TODO' "${here}/manifests/sources.lock"; then
  echo "error: manifests/sources.lock still contains TODO placeholders." >&2
  echo "Pin every source revision (work order §3, §9.1) before building." >&2
  exit 1
fi

echo "error: scripts/build-image.sh build steps are not implemented yet." >&2
exit 1
