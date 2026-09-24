#!/usr/bin/env bash
# Assemble a flashable PB2 CAN Carrier microSD .img by driving
# beagleboard/image-builder directly, instead of re-deriving its U-Boot/
# TI-firmware-signing pipeline ourselves. See image-builder/README.md for
# the real findings this script encodes (confirmed by actually running
# it once, successfully, end to end).
#
# Prerequisites beyond scripts/build-image.sh's own (Debian/Ubuntu host,
# real sudo/root -- this does loop-device and chroot operations):
#   debhelper build-essential dpkg-dev qemu-user-static binfmt-support
#   debootstrap tree m4
# For a non-arm64 host, binfmt_misc must have qemu-aarch64 registered
# (installing qemu-user-static + binfmt-support does this automatically
# on Debian/Ubuntu).
#
# Output: release/pocketbeagle2-<name>-4gb.img + SHA256SUMS.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="${PB2_BUILD_DIR:-${here}/.build}"
release="${here}/release"

log() { printf '\n[assemble-image] %s\n' "$1"; }

kdir="${work}/kernel-build"
kernel_src="${kdir}/KERNEL"
ddir="${work}/dts"
ibdir="${work}/image-builder"

if [ ! -f "${kernel_src}/.config" ] || [ ! -f "${ddir}/src/arm64/overlays/k3-am62-pocketbeagle2-can-carrier.dtbo" ]; then
	echo "error: run scripts/build-image.sh first (kernel tree / overlay not prepared)." >&2
	exit 1
fi

# ---------------------------------------------------------------------
# 1. Package our patched, configured kernel as a real .deb.
# ---------------------------------------------------------------------
log "Kernel: building .deb package (make bindeb-pkg)"
( cd "${kernel_src}" && \
  make -j"$(nproc)" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
    KBUILD_DEBARCH=arm64 \
    LOCALVERSION=-arm64-k3-r56 \
    KDEB_PKGVERSION=1xross \
    KDEB_SOURCENAME=linux-upstream \
    KDEB_COMPRESS=xz \
    DEB_BUILD_PROFILES=pkg.linux-upstream.nokernelheaders \
    bindeb-pkg )
mkdir -p "${kdir}/deploy"
mv "${kdir}"/*.deb "${kdir}"/*.buildinfo "${kdir}"/*.changes "${kdir}/deploy/" 2>/dev/null || true
ls "${kdir}/deploy/"linux-image-*.deb >/dev/null

# ---------------------------------------------------------------------
# 2. Clone + patch beagleboard/image-builder at the pinned commit.
# ---------------------------------------------------------------------
log "image-builder: preparing pinned source + carrier integration"
if [ ! -d "${ibdir}" ]; then
	git clone https://github.com/beagleboard/image-builder.git "${ibdir}"
fi
git -C "${ibdir}" checkout 3ca3705ad2a84f693180da13676fc779f3bcf646
git -C "${ibdir}" apply --check "${here}/image-builder/rootstock-ng-carrier-hook.patch" 2>/dev/null \
	|| echo "  (hook patch already applied or tree differs -- continuing)"
git -C "${ibdir}" apply "${here}/image-builder/rootstock-ng-carrier-hook.patch" 2>/dev/null || true
cp "${here}/image-builder/pb2-carrier-local-repo.sh" "${ibdir}/scripts/"
cp "${here}/image-builder/pb2-can-carrier-debian-trixie-iot.conf" "${ibdir}/configs/"
chmod +x "${ibdir}/RootStock-NG.sh" "${ibdir}/scripts/"*.sh

# ---------------------------------------------------------------------
# 3. Run the real image-builder pipeline (debootstrap + chroot), with
#    our kernel .deb installed via its repo_external mechanism in place
#    of BeagleBoard's stock bbb.io-kernel-6.18-k3.
# ---------------------------------------------------------------------
log "image-builder: running RootStock-NG.sh (debootstrap + chroot -- this is the slow part)"
# RootStock-NG.sh resolves its config/ directory relative to $PWD, not its
# own script location -- must cd into ibdir first or it prints "Invalid
# *.conf" (found by actually running this script end to end).
( cd "${ibdir}" && \
  PB2_CARRIER_DEB_DIR="${kdir}/deploy" \
  bash ./RootStock-NG.sh -c pb2-can-carrier-debian-trixie-iot )

# shellcheck disable=SC1091
source "${ibdir}/.project"
# shellcheck disable=SC2154 # export_filename comes from .project, sourced above
deploy_dir="${ibdir}/deploy/${export_filename}"

log "image-builder: verifying our carrier kernel landed in the built rootfs"
# dpkg-list.txt is `dpkg -l` output: "ii  <pkg> <ver> <arch> <desc>" --
# the package name is NOT at column 0 (found by actually running this
# script end to end; the old ^-anchored pattern never matched and failed
# the build even though the correct kernel package was installed).
grep -qE "^ii +linux-image-[^ ]*-arm64-k3-r56 " "${deploy_dir}/dpkg-list.txt"

# ---------------------------------------------------------------------
# 4. Produce the flashable .img (real PocketBeagle 2 hwpack, swap
#    variant, 4GB) with BeagleBoard's own setup_sdcard.sh.
# ---------------------------------------------------------------------
log "image-builder: setup_sdcard.sh --img-4gb --dtb pocketbeagle2-swap"
( cd "${deploy_dir}" && \
  sudo bash ./setup_sdcard.sh --img-4gb "pocketbeagle2-${export_filename}" --dtb pocketbeagle2-swap )
img="${deploy_dir}/pocketbeagle2-${export_filename}-4gb.img"
ls "${img}"

# ---------------------------------------------------------------------
# 5. Carrier-specific finalization: inject our .dtbo and the FDTOVERLAYS
#    + console APPEND lines into the real extlinux.conf, without
#    touching any of the stock labels (kept for fallback/debug).
# ---------------------------------------------------------------------
log "Injecting carrier overlay + extlinux entry into the boot partition"
mnt="$(mktemp -d)"
loopdev="$(sudo losetup -f)"
sudo losetup -o 1048576 --sizelimit $((524288 * 512)) "${loopdev}" "${img}"
sudo mount "${loopdev}" "${mnt}"
sudo cp "${ddir}/src/arm64/overlays/k3-am62-pocketbeagle2-can-carrier.dtbo" "${mnt}/overlays/"

python3 - "${mnt}/extlinux/extlinux.conf" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path) as f:
	content = f.read()
content = content.replace(
	"default microSD (default)",
	"default PB2 CAN Carrier",
	1,
)
carrier_label = """label PB2 CAN Carrier
    kernel /Image.gz
    append console=ttyS2,115200n8 earlycon=ns16550a,mmio32,0x02860000 root=/dev/mmcblk1p3 ro rootfstype=ext4 fsck.repair=yes resume=/dev/mmcblk1p2 rootwait net.ifnames=0
    fdtdir /
    fdtoverlays /overlays/k3-am62-pocketbeagle2-can-carrier.dtbo
    #initrd /initrd.img

label microSD (failsafe)"""
content = content.replace("label microSD (failsafe)", carrier_label, 1)
with open(path, "w") as f:
	f.write(content)
PYEOF

sudo cat "${mnt}/extlinux/extlinux.conf" | head -10

sync
sudo umount "${mnt}"
sudo losetup -d "${loopdev}"
rmdir "${mnt}"

# ---------------------------------------------------------------------
# 6. Ship the result.
# ---------------------------------------------------------------------
mkdir -p "${release}"
final="${release}/$(basename "${img}")"
cp "${img}" "${final}"
( cd "${release}" && sha256sum "$(basename "${final}")" >> SHA256SUMS )

log "Done: ${final}"
log "Default login: debian / temppwd (see image-builder/README.md for the sysconf.txt override)."
