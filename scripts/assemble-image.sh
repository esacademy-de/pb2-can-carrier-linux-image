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
# 5b. Enable a login getty on MAIN_UART6 (ttyS2) only. Carrier UART0
#     (ttyS7) does NOT get a getty -- it's dedicated exclusively to
#     journald's forwarded output (see 5c below), full session, not just
#     during boot.
#
#     A getty on ttyS7 alongside journald's TTYPath was tried and
#     reverted after three distinct, escalating failures on real
#     hardware: (1) serial-getty@ttyS7's stock TTYVHangup=yes severs
#     journald's already-open connection to the tty the moment the
#     getty starts, going silent for the rest of boot; (2) disabling
#     that (TTYVHangup=no) fixed (1) but exposed that nothing then
#     configures ttyS7's baud rate before journald's early writes,
#     producing a burst of garbage/NUL bytes (fixed separately in 5c
#     below, independent of getty entirely); (3) TTYVHangup=no then
#     caused agetty on ttyS7 to not terminate cleanly on shutdown,
#     stalling reboot/poweroff for ~25s waiting to "abandon session
#     scope" -- a real regression, not acceptable for an unattended
#     deployment. Dedicating ttyS7 to journald only removes the
#     conflict at its root instead of chasing further getty-side
#     workarounds. Login stays available via ttyS2, the USB-C CDC-ACM
#     gadget, and SSH.
# ---------------------------------------------------------------------
log "Enabling serial-getty on ttyS2 (MAIN_UART6) only"
rmnt="$(mktemp -d)"
rloopdev="$(sudo losetup -P -f --show "${img}")"
sudo mount "${rloopdev}p3" "${rmnt}"
sudo ln -sf /usr/lib/systemd/system/serial-getty@.service \
	"${rmnt}/etc/systemd/system/getty.target.wants/serial-getty@ttyS2.service"
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
#     (kernel messages + every systemd status event) instead, for the
#     entire session now that ttyS7 has no getty contending for it.
# ---------------------------------------------------------------------
log "Routing journald's forwarded console output to ttyS7 (carrier UART0) only"
sudo mkdir -p "${rmnt}/etc/systemd/journald.conf.d"
printf '[Journal]\nForwardToConsole=yes\nTTYPath=/dev/ttyS7\n' \
	| sudo tee "${rmnt}/etc/systemd/journald.conf.d/pb2-carrier-uart0-forward.conf" >/dev/null
sudo cat "${rmnt}/etc/systemd/journald.conf.d/pb2-carrier-uart0-forward.conf"

# Nothing at the kernel level configures ttyS7's baud rate -- it's not a
# kernel console= target (only ttyS2 is), so the kernel's own console
# driver setup never touches it, and (per 5b above) there's no getty on
# ttyS7 either to set it as a side effect of starting up. Without this
# fix, journald's early writes -- systemd-journald starts around 5-6s
# into boot, well before anything else would ever touch this tty --
# come out as a long burst of garbage/NUL bytes on a 115200 listener,
# confirmed on real hardware; a manual `stty` command fixed it
# immediately (both the manual test and journald's own subsequent
# writes came through clean afterward), which is what this ExecStartPre
# now does automatically, before journald's first write.
log "Forcing ttyS7 to 115200 8N1 before journald starts writing to it"
sudo mkdir -p "${rmnt}/etc/systemd/system/systemd-journald.service.d"
printf '[Service]\nExecStartPre=/usr/bin/stty -F /dev/ttyS7 115200 raw -echo\n' \
	| sudo tee "${rmnt}/etc/systemd/system/systemd-journald.service.d/pb2-carrier-ttyS7-baud.conf" >/dev/null
sudo cat "${rmnt}/etc/systemd/system/systemd-journald.service.d/pb2-carrier-ttyS7-baud.conf"

# bb-usb-gadgets.service (BeagleBoard's own NCM network + CDC-ACM serial
# USB gadget over USB-C) hangs boot/reboot when VBUS is present without
# a real USB host ever completing enumeration to unblock its DWC3
# gadget driver -- confirmed on real hardware with wall power AND with
# power through the same P1 header pins the carrier board itself uses
# for power, i.e. this is not just a USB-C bench-power artifact, it
# reproduces on the actual carrier power path too. Confirmed pre-
# existing on stock, unmodified BeagleBoard images (not introduced by
# anything in this carrier's own config) and confirmed to never occur
# when powered via a PC's USB-C port (a real host completes enumeration
# and unblocks it). Disabled by default here so boot/reboot is reliable
# regardless of power source; re-enable manually
# (`sudo systemctl enable --now bb-usb-gadgets.service`) if USB gadget
# mode (NCM network / CDC-ACM serial over USB-C) is specifically needed
# -- it works fine as long as a real USB host is actually attached.
log "Disabling bb-usb-gadgets.service by default (hangs boot/reboot without a real USB host)"
sudo rm -f "${rmnt}/etc/systemd/system/multi-user.target.wants/bb-usb-gadgets.service"

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
