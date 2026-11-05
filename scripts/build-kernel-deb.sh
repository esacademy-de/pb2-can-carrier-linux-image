#!/usr/bin/env bash
# Package the configured carrier kernel tree as linux-image-<release>_<version>_arm64.deb
# (plus linux-libc-dev) with the kernel's own "make bindeb-pkg".
#
# usage: scripts/build-kernel-deb.sh <kernel-tree> <outdir> [version]
# The kernel tree must be patched and configured (scripts/build-image.sh).
# version defaults to scripts/kernel-version.sh.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ $# -ge 2 ] || { echo "usage: $0 <kernel-tree> <outdir> [version]" >&2; exit 2; }
kernel_src="$(cd "$1" && pwd)"
outdir="$2"
version="${3:-$(bash "${here}/scripts/kernel-version.sh")}"

( cd "${kernel_src}" && \
  make -j"$(nproc)" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
    KBUILD_DEBARCH=arm64 \
    LOCALVERSION=-arm64-k3-r56 \
    KDEB_PKGVERSION="${version}" \
    KDEB_SOURCENAME=linux-upstream \
    KDEB_COMPRESS=xz \
    DEB_BUILD_PROFILES=pkg.linux-upstream.nokernelheaders \
    bindeb-pkg )

# bindeb-pkg writes next to the kernel tree
mkdir -p "${outdir}"
parent="$(dirname "${kernel_src}")"
mv "${parent}"/*.deb "${parent}"/*.buildinfo "${parent}"/*.changes "${outdir}/" 2>/dev/null || true
ls "${outdir}"/linux-image-*.deb
