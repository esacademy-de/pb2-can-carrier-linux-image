# PB2 CAN Carrier — Linux Image

Reproducible Debian/Linux BSP for the PocketBeagle 2 CAN Carrier baseboard
(triple CAN‑FD, Gigabit Ethernet, USB host, carrier UART0 console, SPI2,
J3 GPIO breakout).

Implementation basis: `PB2_CAN_Carrier_Linux_Image_Work_Order.typ` (hardware
project `trunk/Documents/`), KiCad project V1.0 plus the owner corrections
recorded in that document's §2.

## Status

See [RELEASE_NOTES.md](RELEASE_NOTES.md) for the current, honest state.
Short version: a full kernel build (6.18.37 + PREEMPT_RT + the complete
K3 patch series) succeeds locally; both required kernel patches apply on
top of that fully-patched tree and compile clean; the carrier
device-tree overlay compiles clean and applies with `fdtoverlay` onto
the real base `.dtb`; U-Boot's own source builds clean with the real
defconfig; the main_spi0/GPIO1_17 pinmux conflict found in review is
fixed and verified. Final image assembly is in progress: driving
`beagleboard/image-builder` directly (it installs prebuilt kernel/U-Boot
`.deb` packages rather than building from source, so the plan is to feed
it our own carrier kernel package via its `repo_external` mechanism)
rather than re-deriving U-Boot's TI-firmware signing pipeline ourselves.
Not yet done: finishing that pipeline run, the carrier `.dtbo`/extlinux
post-processing step on top of it, and all hardware validation (work
order §11) — this is a software/DT bring-up handoff, not yet a flashable
release.

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
scripts/build-image.sh              kernel + U-Boot + Debian image build entry point
scripts/flash-and-verify.sh         microSD flash + hardware smoke test entry point (self-hosted runner)
tests/                              automated validation scripts, one per §11 test ID
release/                            generated: image, SHA256SUMS, build log (not committed)
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
scripts/build-image.sh
```

Builds the kernel and the carrier device-tree overlay from the pinned
sources in `manifests/sources.lock` (work order §3, §9.1) and validates
both against the real, patched kernel tree. U-Boot's final firmware
packaging and Debian rootfs assembly are not yet wired into this script
— see [RELEASE_NOTES.md](RELEASE_NOTES.md) limitation #1 for the current
plan (driving `beagleboard/image-builder` directly) and status.
