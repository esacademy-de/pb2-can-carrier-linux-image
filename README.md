# PB2 CAN Carrier — Linux Image

Reproducible Debian/Linux BSP for the PocketBeagle 2 CAN Carrier baseboard
(triple CAN‑FD, Gigabit Ethernet, USB host, optional carrier UART0
console, SPI2, J3 GPIO breakout).

Implementation basis: `PB2_CAN_Carrier_Linux_Image_Work_Order.typ` (hardware
project `trunk/Documents/`), KiCad project V1.0 plus the owner corrections
recorded in that document's §2.

## Status

See [RELEASE_NOTES.md](RELEASE_NOTES.md) for the current, honest state.
Short version: **`scripts/assemble-image.sh` has produced a real,
complete, flashable microSD `.img`** — our patched/configured kernel,
packaged as a `.deb` and installed into a real `beagleboard/image-builder`
debootstrap+chroot build in place of BeagleBoard's stock kernel package,
turned into a bootable image with BeagleBoard's own (already TI-signed)
U-Boot firmware via `setup_sdcard.sh`, with the carrier device-tree
overlay and a new default extlinux boot entry injected on top. All the
component-level validation that came before this still stands: both
kernel patches compile clean against the fully-patched tree, the carrier
overlay compiles clean and merges with `fdtoverlay`, and the
main_spi0/GPIO1_17 pinmux conflict found in review is fixed. What's left:
all hardware validation (work order §11) — that's the next and last
step, and it's yours to do.

## Layout

```
manifests/sources.lock              pinned repo/commit list
RELEASE_NOTES.md                    current status + known limitations
configs/kernel.fragment             kernel config fragment
configs/uboot.fragment              U-Boot config fragment
patches/kernel/                     TCAN3413 binding/driver + M_CAN sequencing patches
dts/                                carrier device-tree overlay(s)
dts/optional-spi-children/          composable SPI child-device overlays (not in base overlay)
image/package-list.txt              rootfs package list
image/pb2-config.txt                user-editable config on the SD card's FAT partition (SSH on/off, password logins)
image/pb2-boot-config.{sh,service}  applies that file at every boot (installed by assemble-image.sh)
image-builder/                      beagleboard/image-builder integration (patch, config, hook script) + real findings
scripts/build-image.sh              kernel + device-tree overlay build/validate entry point
scripts/assemble-image.sh           full pipeline: kernel .deb -> image-builder -> flashable .img
scripts/flash-and-verify.sh         microSD flash + hardware smoke test entry point (self-hosted runner)
tests/                              automated validation scripts, one per §11 test ID
release/                            generated: image, SHA256SUMS (not committed -- multi-GB, see below)
```

## Build environment

- **Cross-compile / static-analysis CI**: GitHub-hosted `ubuntu-latest`
  runner ([.github/workflows/build.yml](.github/workflows/build.yml)). Runs
  on every push: shellcheck, `git am`-validates both kernel patches against
  the pinned kernel commit, and compiles + `fdtoverlay`-merges the carrier
  device-tree overlay against the pinned base `.dtb`. Deliberately does
  *not* build the full kernel Image/U-Boot/Debian image on every push (too
  slow/heavy for the hosted runner's disk and time budget) — that full
  build has been run and validated locally instead (see
  [RELEASE_NOTES.md](RELEASE_NOTES.md)). No special hardware required for
  this job.
- **Hardware validation**: a self-hosted GitHub Actions runner attached to a
  bench machine with the PB2 + CAN carrier connected
  ([.github/workflows/hardware-validation.yml](.github/workflows/hardware-validation.yml)).
  Manual `workflow_dispatch` trigger until a runner labeled `pb2-bench` is
  registered (`Settings → Actions → Runners → New self-hosted runner`).
  Tests needing a scope/logic analyzer or camera (CAN-01 reset safety,
  ETH-05 RJ45 LED colors) stay manual/documented steps with captured
  evidence attached to the run, per work order §11.

## Reproducing a build

```bash
scripts/build-image.sh      # kernel + carrier overlay: build + validate
scripts/assemble-image.sh   # -> flashable microSD .img (needs real sudo/root)
```

`build-image.sh` builds the kernel and the carrier device-tree overlay
from the pinned sources in `manifests/sources.lock` (work order §3,
§9.1) and validates both against the real, patched kernel tree.
`assemble-image.sh` picks up from there and drives
`beagleboard/image-builder` directly to produce a real, flashable
`release/pocketbeagle2-*-4gb.img` — see
[image-builder/README.md](image-builder/README.md) for exactly what that
does and the real findings behind it, and
[RELEASE_NOTES.md](RELEASE_NOTES.md) for current status. Needs a
Debian/Ubuntu host (or WSL) with real `sudo`/root — it does loop-device
and `chroot` operations under QEMU arm64 emulation, and the debootstrap
stage alone can take significant time.

Write `release/pocketbeagle2-*-4gb.img` to a microSD card with
balenaEtcher, Raspberry Pi Imager, `dd`, or any other raw-image writer.
Default login is `debian` / `temppwd` (root disabled) — override it
without rebuilding by editing `sysconf.txt` on the FAT boot partition
before first boot (`user_password`, `user_authorized_key`, `hostname`), or
via BeagleBoard's own Imaging Utility. The default password is a one-time
password: it is expired in the image, so the first login (serial console or
SSH) forces choosing a new one. Key logins get the same prompt and need a
terminal for it (`ssh -t`); a script or `ssh host command` fails with
"Password change required but no TTY available" until it was changed once.

**SSH over Ethernet** is on by default and is switched by `pb2-config.txt`
on the same FAT boot partition (`/boot/firmware/pb2-config.txt` on the
running system), applied at every boot before the SSH server starts:

```
ssh=enabled              # or: disabled  (no SSH server at all)
ssh_password_auth=yes    # or: no  (key logins only; ignored unless an
                         #  authorized key is installed, so no lock-out)
```

Add a public key for key-only login via `user_authorized_key=` in
`sysconf.txt`. The first boot of a freshly written card regenerates the SSH
host keys (so no two units share keys) and reboots once. To apply a change
without rebooting: `sudo pb2-boot-config --apply-now`.

**USB gadget mode (NCM network / CDC-ACM serial over USB-C) is
disabled by default** (`bb-usb-gadgets.service`). Confirmed on real
hardware: it hangs boot/reboot whenever VBUS is present without a real
USB host to complete enumeration — reproduces on wall-adapter power
and on the carrier's own P1 power pins, not just USB-C bench power, and
is pre-existing on stock BeagleBoard images too (not introduced by
anything here). It works fine, and only when, a real PC is attached to
actually enumerate it; enable it manually when needed:
`sudo systemctl enable --now bb-usb-gadgets.service`.

**Console**: default is stock MAIN_UART6 (SPL, U-Boot, kernel, login),
matching an unmodified PocketBeagle 2 (work order D-12). Carrier UART0
(P1.30/P1.32) is fully implemented and confirmed working, but is a
manual, reboot-time override — edit `console=ttyS2,115200n8` to
`console=ttyS7,115200n8` in the "PB2 CAN Carrier" label's `append` line
in `/extlinux/extlinux.conf` on the flashed boot partition (leave
`earlycon=` unchanged). Never list both `ttyS2` and `ttyS7` as active
consoles at once — see `configs/uboot.fragment` for why. A login getty
is enabled on **both** `ttyS2` and `ttyS7`. `ttyS7`/UART0 additionally
carries journald's forwarded output (kernel messages plus every
systemd status event, `ForwardToConsole=yes`/`TTYPath=/dev/ttyS7`) at
the same time — confirmed stable on real hardware across multiple
reboots and power cycles, after working through three real issues
(severed journald connection, baud-rate garbage, and an apparent
reboot hang that turned out to be caused by `bb-usb-gadgets.service`,
not the getty itself — see `configs/uboot.fragment` for the full
story). In the default configuration, kernel log output
(`dmesg`) stays on `ttyS2`/MAIN_UART6 only (`systemd.show_status=no`
stops PID1's own status writer from also touching that console) — see
`configs/uboot.fragment` for why they're split this way.
