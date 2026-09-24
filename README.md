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
before first boot, or via BeagleBoard's own Imaging Utility. Document
this properly before handing the image to anyone else.

**Console**: default is stock MAIN_UART6 (SPL, U-Boot, kernel, login),
matching an unmodified PocketBeagle 2 (work order D-12). Carrier UART0
(P1.30/P1.32) is fully implemented and confirmed working, but is a
manual, reboot-time override — edit `console=ttyS2,115200n8` to
`console=ttyS7,115200n8` in the "PB2 CAN Carrier" label's `append` line
in `/extlinux/extlinux.conf` on the flashed boot partition (leave
`earlycon=` unchanged). Never list both `ttyS2` and `ttyS7` as active
consoles at once — see `configs/uboot.fragment` for why. A login getty
is enabled on **both** `ttyS2` and `ttyS7` unconditionally (independent
of which is the active kernel console), so you can log in on whichever
UART you're physically connected to without touching `extlinux.conf` at
all — only the kernel log's destination requires the manual edit above.
In the default configuration, kernel log output (`dmesg`) and systemd's
own status output are deliberately on different UARTs: raw kernel
printk stays on `ttyS2`/MAIN_UART6 only (`systemd.show_status=no`), and
systemd's own status stream is forwarded to `ttyS7`/UART0 exclusively
via journald (`ForwardToConsole=yes`/`TTYPath=/dev/ttyS7`) — see
`configs/uboot.fragment` for why they're split this way.
