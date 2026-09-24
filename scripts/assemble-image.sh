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
# NOT named "release": image-builder's own .project (sourced below,
# from the .conf's own "release" var, e.g. "13.7") clobbers a same-named
# variable when sourced -- found by actually running this script end to
# end, which silently wrote the final image to a wrong relative path.
release_dir="${here}/release"

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

sudo python3 - "${mnt}/extlinux/extlinux.conf" <<'PYEOF'
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
    append console=ttyS2,115200n8 earlycon=ns16550a,mmio32,0x02860000 systemd.show_status=no root=/dev/mmcblk1p3 ro rootfstype=ext4 fsck.repair=yes resume=/dev/mmcblk1p2 rootwait net.ifnames=0
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
# 5b. Enable a login getty on BOTH MAIN_UART6 (ttyS2) and carrier UART0
#     (ttyS7), unconditionally -- independent of which one is the
#     active kernel console= at any given time.
#
#     systemd's own getty-generator only creates a getty for whatever
#     tty is named in the kernel's console= argument at boot. Since only
#     ONE of ttyS2/ttyS7 is ever in console= at a time (registering both
#     as simultaneous KERNEL CONSOLES was confirmed on real hardware to
#     corrupt one of them -- see the UART0/UART6 exclusivity note in
#     configs/uboot.fragment), the OTHER tty would otherwise have no
#     login prompt at all. A getty is just agetty listening on a tty --
#     unrelated to that kernel printk-console-duplication bug -- so
#     statically enabling both here is safe and does not reintroduce it;
#     confirmed empirically: /etc/systemd/system/getty.target.wants/
#     only had the console-driven getty (dynamically generated) and
#     tty1's own statically-enabled getty -- the non-default UART's
#     getty was genuinely absent, not just hidden.
# ---------------------------------------------------------------------
log "Enabling serial-getty on both ttyS2 (MAIN_UART6) and ttyS7 (carrier UART0)"
rmnt="$(mktemp -d)"
rloopdev="$(sudo losetup -P -f --show "${img}")"
sudo mount "${rloopdev}p3" "${rmnt}"
for tty in ttyS2 ttyS7; do
	sudo ln -sf /usr/lib/systemd/system/serial-getty@.service \
		"${rmnt}/etc/systemd/system/getty.target.wants/serial-getty@${tty}.service"
done
sudo ls -la "${rmnt}/etc/systemd/system/getty.target.wants/"

# ---------------------------------------------------------------------
# 5c. Split kernel printk (UART6/ttyS2, via console= above) from all of
#     systemd's own output (UART0/ttyS7 exclusively), via journald's own
#     ForwardToConsole=/TTYPath= -- NOT via a second kernel console=,
#     which was confirmed on real hardware to corrupt UART6 at the
#     ttyS7 driver handoff (see the UART0/UART6 exclusivity note in
#     configs/uboot.fragment). journald forwarding is a userspace-only
#     mechanism, independent of kernel console registration, so it
#     carries none of that risk. Combined with systemd.show_status=no
#     above (which stops PID1's own direct status writer from touching
#     /dev/console, i.e. ttyS2), UART6 becomes pure, uninterrupted
#     kernel printk output, and UART0 gets journald's full stream
#     (kernel messages + every systemd status event) instead.
# ---------------------------------------------------------------------
log "Routing journald's forwarded console output to ttyS7 (carrier UART0) only"
sudo mkdir -p "${rmnt}/etc/systemd/journald.conf.d"
printf '[Journal]\nForwardToConsole=yes\nTTYPath=/dev/ttyS7\n' \
	| sudo tee "${rmnt}/etc/systemd/journald.conf.d/pb2-carrier-uart0-forward.conf" >/dev/null
sudo cat "${rmnt}/etc/systemd/journald.conf.d/pb2-carrier-uart0-forward.conf"

# serial-getty@.service's own TTYVHangup=yes performs a vhangup(2) on
# the tty as part of starting up, which disconnects any process already
# holding that device open -- including journald's own TTYPath
# connection above, established earlier in boot (systemd-journald.service
# starts well before getty.target). Confirmed on real hardware: without
# this override, UART0 goes completely silent for the rest of boot the
# moment serial-getty@ttyS7 starts, even though journald's forwarding
# config is present and correct. Override it for the ttyS7 instance only
# -- ttyS2's getty has no such conflict (nothing else uses ttyS2 as a
# forwarding target), so it's left with the stock TTYVHangup=yes.
log "Disabling TTYVHangup for serial-getty@ttyS7 (would sever journald's UART0 connection)"
sudo mkdir -p "${rmnt}/etc/systemd/system/serial-getty@ttyS7.service.d"
printf '[Service]\nTTYVHangup=no\n' \
	| sudo tee "${rmnt}/etc/systemd/system/serial-getty@ttyS7.service.d/override.conf" >/dev/null
sudo cat "${rmnt}/etc/systemd/system/serial-getty@ttyS7.service.d/override.conf"

sync
sudo umount "${rmnt}"
sudo losetup -d "${rloopdev}"
rmdir "${rmnt}"

# ---------------------------------------------------------------------
# 6. Ship the result.
# ---------------------------------------------------------------------
mkdir -p "${release_dir}"
final="${release_dir}/$(basename "${img}")"
cp "${img}" "${final}"
( cd "${release_dir}" && sha256sum "$(basename "${final}")" >> SHA256SUMS )

log "Done: ${final}"
log "Default login: debian / temppwd (see image-builder/README.md for the sysconf.txt override)."
