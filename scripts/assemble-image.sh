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

# PB2_KERNEL_DEB=<linux-image .deb>: use a kernel package that was built before
# (for example the one from the package repository, built by the build-kernel
# workflow) instead of compiling one here. The image then carries exactly the
# kernel that "apt" serves.
if [ ! -f "${ddir}/src/arm64/overlays/k3-am62-pocketbeagle2-can-carrier.dtbo" ] \
	|| { [ -z "${PB2_KERNEL_DEB:-}" ] && [ ! -f "${kernel_src}/.config" ]; }; then
	echo "error: run scripts/build-image.sh first (kernel tree / overlay not prepared), or set PB2_KERNEL_DEB." >&2
	exit 1
fi

# ---------------------------------------------------------------------
# 1. The kernel as a real .deb.
# ---------------------------------------------------------------------
if [ -n "${PB2_KERNEL_DEB:-}" ]; then
	log "Kernel: using the prebuilt package ${PB2_KERNEL_DEB}"
	[ -f "${PB2_KERNEL_DEB}" ] || { echo "error: ${PB2_KERNEL_DEB} not found" >&2; exit 1; }
	dpkg-deb -f "${PB2_KERNEL_DEB}" Package Version
	mkdir -p "${kdir}/deploy"
	rm -f "${kdir}"/deploy/linux-image-*.deb
	cp "${PB2_KERNEL_DEB}" "${kdir}/deploy/"
else
	log "Kernel: building .deb package (make bindeb-pkg)"
	bash "${here}/scripts/build-kernel-deb.sh" "${kernel_src}" "${kdir}/deploy"
fi

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
# The optional overlays (dts/optional-spi-children, switched on with
# "pb2-overlay enable <name>") are compiled with the same device-tree tree
# and go next to the carrier overlay; they are inactive until enabled.
cp "${here}"/dts/optional-spi-children/*.dtso "${ddir}/src/arm64/overlays/"
( cd "${ddir}" && make all_arm64 >/dev/null )
sudo cp "${ddir}/src/arm64/overlays/k3-am62-pocketbeagle2-can-carrier.dtbo" \
	"${ddir}"/src/arm64/overlays/k3-am62-pocketbeagle2-can-carrier-*.dtbo "${mnt}/overlays/"

# User-editable carrier configuration on the SD card's FAT partition
# (SSH on/off, password logins); applied at every boot by
# pb2-boot-config.service (step 5d). Not sysconf.txt: BeagleBoard's
# bbbio-set-sysconf regenerates that file after each boot and has no SSH
# switch.
sudo install -m 0644 "${here}/image/pb2-config.txt" "${mnt}/pb2-config.txt"

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
# 5b. Enable a login getty on BOTH ttyS2 (MAIN_UART6) and ttyS7 (carrier
#     UART0) -- ttyS7 also carries journald's forwarded output (5c
#     below) at the same time.
#
#     History: a getty on ttyS7 alongside journald's TTYPath was tried,
#     reverted, then re-tried and confirmed stable on real hardware.
#     First attempt hit two real, fixed problems: (1) serial-getty@.service's
#     stock TTYVHangup=yes severs journald's already-open TTYPath
#     connection the moment the getty starts (fixed: TTYVHangup=no via
#     the drop-in below); (2) nothing then configured ttyS7's baud rate
#     before journald's early writes, producing garbage/NUL bytes
#     (fixed separately in 5c, independent of getty). A THIRD apparent
#     problem -- reboot/poweroff stalling permanently -- was initially
#     (and incorrectly) attributed to TTYVHangup=no and led to removing
#     the getty entirely. Further investigation found the real cause was
#     unrelated: bb-usb-gadgets.service hanging the USB gadget driver
#     whenever VBUS is present without a real host to complete
#     enumeration (see the bb-usb-gadgets section below) -- confirmed
#     independently of ttyS7/getty entirely (identical hang on stock
#     images with no getty changes at all). With bb-usb-gadgets disabled
#     by default, TTYVHangup=no + a getty on ttyS7 was re-tested and
#     confirmed stable across multiple reboots and power cycles on real
#     hardware.
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

# serial-getty@.service's stock TTYVHangup=yes performs a vhangup(2) on
# the tty as part of starting up, which disconnects any process already
# holding that device open -- including journald's own TTYPath
# connection (5c below), established earlier in boot
# (systemd-journald.service starts well before getty.target). Override
# it for the ttyS7 instance only -- ttyS2's getty has no such conflict
# (nothing else uses ttyS2 as a forwarding target), so it keeps the
# stock TTYVHangup=yes.
log "Disabling TTYVHangup for serial-getty@ttyS7 (would sever journald's UART0 connection)"
sudo mkdir -p "${rmnt}/etc/systemd/system/serial-getty@ttyS7.service.d"
printf '[Service]\nTTYVHangup=no\n' \
	| sudo tee "${rmnt}/etc/systemd/system/serial-getty@ttyS7.service.d/override.conf" >/dev/null
sudo cat "${rmnt}/etc/systemd/system/serial-getty@ttyS7.service.d/override.conf"

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
#     entire session -- confirmed on real hardware to coexist cleanly
#     with ttyS7's login getty (5b above).
# ---------------------------------------------------------------------
log "Routing journald's forwarded console output to ttyS7 (carrier UART0) only"
sudo mkdir -p "${rmnt}/etc/systemd/journald.conf.d"
printf '[Journal]\nForwardToConsole=yes\nTTYPath=/dev/ttyS7\n' \
	| sudo tee "${rmnt}/etc/systemd/journald.conf.d/pb2-carrier-uart0-forward.conf" >/dev/null
sudo cat "${rmnt}/etc/systemd/journald.conf.d/pb2-carrier-uart0-forward.conf"

# Nothing at the kernel level configures ttyS7's baud rate -- it's not a
# kernel console= target (only ttyS2 is), so the kernel's own console
# driver setup never touches it. serial-getty@ttyS7 (5b above) would
# normally be the thing that sets it, but that starts much later in
# boot (~25s+) than systemd-journald (~5-6s), which starts writing to
# /dev/ttyS7 immediately per TTYPath= above. Without this fix, those
# early writes come out as a long burst of garbage/NUL bytes on a
# 115200 listener,
# confirmed on real hardware; a manual `stty` command fixed it
# immediately (both the manual test and journald's own subsequent
# writes came through clean afterward), which is what this ExecStartPre
# now does automatically, before journald's first write.
#
# `raw` alone disables ALL output processing (-opost), which includes
# onlcr -- the flag that translates outgoing \n to \r\n. Confirmed on
# real hardware: without opost/onlcr explicitly re-enabled, every kernel
# log line (which ends in bare \n, per Linux's own internal log format)
# just drops the cursor down a line without returning to column 0,
# producing a cascading/staircase display on a real terminal. `opost
# onlcr` after `raw` restores just that one translation while keeping
# everything else about raw mode (no line editing, no echo).
log "Forcing ttyS7 to 115200 8N1 before journald starts writing to it"
sudo mkdir -p "${rmnt}/etc/systemd/system/systemd-journald.service.d"
printf '[Service]\nExecStartPre=/usr/bin/stty -F /dev/ttyS7 115200 raw -echo opost onlcr\n' \
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

# ---------------------------------------------------------------------
# 5d. SSH over Ethernet, controlled by /boot/firmware/pb2-config.txt on the
#     SD card (image/pb2-config.txt, step 5), plus per-device SSH host keys.
#
#     pb2-boot-config.service runs at every boot, before ssh.service, and
#     turns the SSH server on or off (Debian's sshd_not_to_be_run) and
#     optionally disables password logins (only if an authorized key is
#     installed). ssh.service itself stays enabled, as in the stock image,
#     so the default (key missing / file missing) is SSH enabled.
#
#     Host keys: the stock image ships the keys generated at build time,
#     i.e. every unit built from the same image would share them.
#     BeagleBoard's bbbio-set-sysconf regenerates them at first boot when
#     /etc/bbb.io/ssh_regenerate exists (it then reboots once); that flag
#     is not set by default, so set it here.
# ---------------------------------------------------------------------
log "Enabling ssh.service and arming host key regeneration (pb2-boot-config itself comes with the support package, step 5e)"
sudo ln -sf /usr/lib/systemd/system/ssh.service \
	"${rmnt}/etc/systemd/system/multi-user.target.wants/ssh.service"
sudo mkdir -p "${rmnt}/etc/bbb.io"
sudo touch "${rmnt}/etc/bbb.io/ssh_regenerate"
sudo ls -la "${rmnt}/etc/systemd/system/multi-user.target.wants/" "${rmnt}/etc/bbb.io/ssh_regenerate"

# ---------------------------------------------------------------------
# 5d2. Force a password change at first login. The image ships the public
#      default password debian/temppwd (shown in the login banner as a "one
#      time password"), and SSH is enabled by default (5d), so the default
#      must not stay usable: mark it expired (lastchg = 0, the same as
#      "chage -d 0 debian"). The console getty and password SSH logins then
#      require choosing a new password before anything else. Key logins
#      are asked as well (PAM account check), but need a tty: use "ssh -t".
#      Setting user_password in sysconf.txt replaces this password and
#      its expiry, as before.
# ---------------------------------------------------------------------
log "Expiring the default debian password (forced change at first login)"
sudo sed -i -E 's/^(debian:[^:]*:)[0-9]*:/\10:/' "${rmnt}/etc/shadow"
sudo awk -F: '$1 == "debian" { ok = ($3 == 0 && $2 != "" && $2 !~ /^[!*]/) } END { exit !ok }' "${rmnt}/etc/shadow" \
	|| { echo "error: debian password not marked expired in /etc/shadow" >&2; exit 1; }
sudo awk -F: '$1 == "debian" { print "  debian: lastchg=" $3 ", hash present" }' "${rmnt}/etc/shadow"

# ---------------------------------------------------------------------
# 5e. Carrier support package (pb2-can-carrier-support). One .deb carries
#     everything carrier-specific that lives in the root filesystem, so that a
#     freshly flashed card and a board updated with "apt upgrade" are the same:
#       - pb2-boot-config + unit (SD-card pb2-config.txt: SSH switch), see 5d
#       - pb2-eth-linkdown.service: Ethernet link down on power-off. Confirmed
#         on hardware: nothing in the power-off path closes the interface, so
#         the DP83867 PHY keeps its link (RJ45 LEDs on, switch port up).
#       - pb2-can-names.service: can0/can1/can2 = CAN A/B/C (the kernel's probe
#         order would give can0 = CAN C).
#       - pb2-pmic-poweroff shutdown hook + i2c-dev autoload. Confirmed on
#         hardware: the kernel's power-off path (tps65219 handler, PSCI
#         SYSTEM_OFF) leaves the PMIC running (SoC parked, power LED lit, USB
#         VBUS and PHY powered, power button dead); the same I2C_OFF_REQ sent
#         from userspace switches everything off and the button restarts the
#         board. Runs after services stop and filesystems unmount; poweroff
#         only, and if the PMIC does not react the kernel power-off continues.
#       - the carrier overlay (also copied to the boot partition above)
#       - apt pin: no other kernel package may replace the carrier kernel
#         (any kernel install overwrites /boot/firmware/Image.gz through the
#         zz-uenv_txt hook, and a stock kernel lacks the PHY patches)
#       - the signed package repository (source list + key), the channel for
#         kernel and support updates (apt/README.md)
#     The package is built here from the same files; its postinst enables the
#     units. It is installed with dpkg in the (QEMU-emulated) arm64 rootfs.
# ---------------------------------------------------------------------
log "Installing pb2-can-carrier-support (carrier units, hooks, overlay, apt pin, package repository)"
support_dir="$(mktemp -d)"
support_version="$(bash "${here}/scripts/support-version.sh")"
bash "${here}/scripts/build-support-deb.sh" "${support_version}" "${support_dir}" \
	"${ddir}/src/arm64/overlays/k3-am62-pocketbeagle2-can-carrier.dtbo" \
	"${ddir}"/src/arm64/overlays/k3-am62-pocketbeagle2-can-carrier-*.dtbo
# pb2-can-carrier-kernel: meta package that follows the carrier kernel, so that
# "apt upgrade" on the board installs kernel updates of the package repository.
kernel_deb="$(find "${kdir}/deploy" -name 'linux-image-*.deb' | sort -V | tail -n 1)"
bash "${here}/scripts/build-kernel-meta-deb.sh" "${kernel_deb}" "${support_dir}"
sudo cp "${support_dir}"/pb2-can-carrier-*.deb "${rmnt}/tmp/"
sudo mount -t proc proc "${rmnt}/proc"
sudo chroot "${rmnt}" /bin/sh -c 'dpkg -i /tmp/pb2-can-carrier-support_*.deb /tmp/pb2-can-carrier-kernel_*.deb'
sudo umount "${rmnt}/proc"
sudo rm -f "${rmnt}"/tmp/pb2-can-carrier-*.deb
rm -rf "${support_dir}"
for want in multi-user.target.wants/pb2-boot-config.service \
	multi-user.target.wants/pb2-can-names.service \
	poweroff.target.wants/pb2-eth-linkdown.service halt.target.wants/pb2-eth-linkdown.service; do
	sudo test -L "${rmnt}/etc/systemd/system/${want}" \
		|| { echo "error: ${want} is not enabled" >&2; exit 1; }
done
sudo test -x "${rmnt}/usr/lib/systemd/system-shutdown/pb2-pmic-poweroff.shutdown" \
	|| { echo "error: PMIC power-off hook missing" >&2; exit 1; }
sudo test -f "${rmnt}/etc/modules-load.d/pb2-i2c-dev.conf" \
	|| { echo "error: i2c-dev autoload missing" >&2; exit 1; }
sudo test -x "${rmnt}/usr/sbin/pb2-overlay" \
	|| { echo "error: pb2-overlay missing" >&2; exit 1; }

# ---------------------------------------------------------------------
# 5g. apt: drop the build-time local repository. The kernel .deb reached the
#     rootfs through a throw-away local repo (/opt/pb2-carrier-repo, only a
#     Packages.gz); on the running system it is useless and made every
#     "apt update" print three harmless "File not found - Packages.xz/.bz2/
#     .lzma" errors. The installed kernel package stays. (The kernel pin and
#     the package repository come with pb2-can-carrier-support.)
# ---------------------------------------------------------------------
log "apt: removing the build-time local repository"
sudo rm -f "${rmnt}/etc/apt/sources.list.d/repo_external.list"
sudo rm -rf "${rmnt}/opt/pb2-carrier-repo"
if sudo grep -rq pb2-carrier-repo "${rmnt}/etc/apt/"; then
	echo "error: a reference to the local carrier repo is left in /etc/apt" >&2; exit 1
fi
sudo grep -q '^Pin-Priority: -1' "${rmnt}/etc/apt/preferences.d/pb2-can-carrier-kernel" \
	|| { echo "error: kernel pin not installed" >&2; exit 1; }
sudo grep -q '^URIs: https://esacademy-de.github.io/pb2-can-carrier-linux-image/' \
	"${rmnt}/etc/apt/sources.list.d/pb2-can-carrier.sources" \
	|| { echo "error: package repository not configured" >&2; exit 1; }

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
