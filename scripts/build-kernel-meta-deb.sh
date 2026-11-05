#!/usr/bin/env bash
# Build pb2-can-carrier-kernel, a tiny package that depends on exactly the
# carrier kernel package built from it. Installed on a board (the image has it),
# "apt upgrade" follows every new carrier kernel, also when its package name
# changes with the kernel release.
#
# usage: scripts/build-kernel-meta-deb.sh <linux-image.deb> <outdir>
set -euo pipefail
[ $# -eq 2 ] || { echo "usage: $0 <linux-image.deb> <outdir>" >&2; exit 2; }
kdeb="$1"
outdir="$2"
kpkg="$(dpkg-deb -f "${kdeb}" Package)"
kver="$(dpkg-deb -f "${kdeb}" Version)"
pkg=pb2-can-carrier-kernel

root="$(mktemp -d)"
trap 'rm -rf "${root}"' EXIT
install -d -m 0755 "${root}/DEBIAN" "${root}/usr/share/doc/${pkg}"
cat > "${root}/usr/share/doc/${pkg}/README" <<README
Meta package: follows the PB2 CAN Carrier kernel (${kpkg}).
README
cat > "${root}/DEBIAN/control" <<CONTROL
Package: ${pkg}
Version: ${kver}
Architecture: arm64
Maintainer: esacademy-de <98397027+esacademy-de@users.noreply.github.com>
Depends: ${kpkg} (>= ${kver})
Section: kernel
Priority: optional
Homepage: https://github.com/esacademy-de/pb2-can-carrier-linux-image
Description: PocketBeagle 2 CAN Carrier kernel (meta package)
 Depends on the newest PB2 CAN Carrier kernel of the package repository, so
 that "apt upgrade" installs kernel updates.
CONTROL
mkdir -p "${outdir}"
dpkg-deb --root-owner-group -Zxz --build "${root}" "${outdir}/${pkg}_${kver}_arm64.deb" >/dev/null
echo "${outdir}/${pkg}_${kver}_arm64.deb"
