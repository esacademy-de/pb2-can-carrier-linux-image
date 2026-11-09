#!/usr/bin/env bash
# Build the pb2-can-carrier-support .deb: every carrier-specific file of the
# image (overlay, SD-card config service, Ethernet link-down unit, PMIC
# power-off hook, i2c-dev autoload, apt pin, package repository source and key)
# in one package, so that a fresh image and an updated board end up identical.
#
# usage: scripts/build-support-deb.sh <version> <outdir> <overlay.dtbo> [optional-overlay.dtbo ...]
# The first overlay is the carrier overlay, the others are the optional ones
# (see dts/optional-spi-children/); all are shipped in the package.
# The version must increase with every change to the packaged files; use
# scripts/support-version.sh.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ $# -ge 3 ] || { echo "usage: $0 <version> <outdir> <overlay.dtbo> [optional-overlay.dtbo ...]" >&2; exit 2; }
version="$1"
outdir="$2"
shift 2
for dtbo in "$@"; do
	[ -f "${dtbo}" ] || { echo "error: overlay ${dtbo} not found" >&2; exit 1; }
done

pkg=pb2-can-carrier-support
root="$(mktemp -d)"
trap 'rm -rf "${root}"' EXIT

install -d -m 0755 "${root}/DEBIAN" \
	"${root}/usr/sbin" \
	"${root}/usr/lib/systemd/system" \
	"${root}/usr/lib/systemd/system-shutdown" \
	"${root}/usr/lib/systemd/system/serial-getty@.service.d" \
	"${root}/usr/share/keyrings" \
	"${root}/usr/share/pb2-can-carrier/overlays" \
	"${root}/usr/share/doc/${pkg}" \
	"${root}/etc/apt/preferences.d" \
	"${root}/etc/apt/sources.list.d" \
	"${root}/etc/modules-load.d"

install -m 0755 "${here}/image/pb2-boot-config.sh"         "${root}/usr/sbin/pb2-boot-config"
install -m 0644 "${here}/image/pb2-boot-config.service"   "${root}/usr/lib/systemd/system/pb2-boot-config.service"
install -m 0644 "${here}/image/pb2-eth-linkdown.service"   "${root}/usr/lib/systemd/system/pb2-eth-linkdown.service"
install -m 0644 "${here}/image/pb2-serial-getty-no-reset.conf" "${root}/usr/lib/systemd/system/serial-getty@.service.d/pb2-no-tty-reset.conf"
install -m 0755 "${here}/image/pb2-pmic-poweroff.shutdown" "${root}/usr/lib/systemd/system-shutdown/pb2-pmic-poweroff.shutdown"
install -m 0644 "${here}/image/pb2-i2c-dev.conf"           "${root}/etc/modules-load.d/pb2-i2c-dev.conf"
install -m 0644 "${here}/image/pb2-apt-preferences"        "${root}/etc/apt/preferences.d/pb2-can-carrier-kernel"
install -m 0644 "${here}/apt/support/pb2-can-carrier.sources" "${root}/etc/apt/sources.list.d/pb2-can-carrier.sources"
install -m 0644 "${here}/apt/pb2-can-carrier-archive-keyring.gpg" "${root}/usr/share/keyrings/pb2-can-carrier-archive-keyring.gpg"
install -m 0755 "${here}/image/pb2-overlay.py"             "${root}/usr/sbin/pb2-overlay"
install -d -m 0755 "${root}/usr/lib/udev/rules.d"
install -m 0644 "${here}/image/pb2-spidev.rules"           "${root}/usr/lib/udev/rules.d/80-pb2-spidev.rules"
for dtbo in "$@"; do
	install -m 0644 "${dtbo}" "${root}/usr/share/pb2-can-carrier/overlays/$(basename "${dtbo}")"
done
install -m 0644 "${here}/apt/README.md" "${root}/usr/share/doc/${pkg}/README.md"
cat > "${root}/usr/share/doc/${pkg}/copyright" <<'COPYRIGHT'
PB2 CAN Carrier support files. Source, licences and history:
https://github.com/esacademy-de/pb2-can-carrier-linux-image
COPYRIGHT
chmod 0644 "${root}/usr/share/doc/${pkg}/copyright"

install -m 0755 "${here}/apt/support/postinst" "${root}/DEBIAN/postinst"
install -m 0755 "${here}/apt/support/postrm"   "${root}/DEBIAN/postrm"
cat > "${root}/DEBIAN/conffiles" <<'CONFFILES'
/etc/apt/preferences.d/pb2-can-carrier-kernel
/etc/apt/sources.list.d/pb2-can-carrier.sources
/etc/modules-load.d/pb2-i2c-dev.conf
CONFFILES

size_kb=$(du -sk "${root}" | cut -f1)
cat > "${root}/DEBIAN/control" <<CONTROL
Package: ${pkg}
Version: ${version}
Architecture: arm64
Maintainer: esacademy-de <98397027+esacademy-de@users.noreply.github.com>
Installed-Size: ${size_kb}
Depends: python3, systemd, iproute2, init-system-helpers
Section: admin
Priority: optional
Homepage: https://github.com/esacademy-de/pb2-can-carrier-linux-image
Description: PocketBeagle 2 CAN Carrier support files
 Carrier overlay (plus optional ones, switched with pb2-overlay),
 SD-card configuration (SSH switch), Ethernet link-down on power-off, real
 PMIC power-off, apt pin that keeps the carrier kernel, and the signed package
 repository of the PB2 CAN Carrier.
CONTROL

mkdir -p "${outdir}"
dpkg-deb --root-owner-group -Zxz --build "${root}" "${outdir}/${pkg}_${version}_arm64.deb" >/dev/null
echo "${outdir}/${pkg}_${version}_arm64.deb"
