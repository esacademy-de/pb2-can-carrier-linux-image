# PB2 CAN Carrier — Linux Image

Reproducible Debian/Linux BSP for the PocketBeagle 2 CAN Carrier baseboard
(triple CAN‑FD, Gigabit Ethernet, USB host, carrier UART0 console, SPI2,
J3 GPIO breakout).

Implementation basis: `PB2_CAN_Carrier_Linux_Image_Work_Order.typ` (hardware
project `trunk/Documents/`), KiCad project V1.0 plus the owner corrections
recorded in that document's §2.

## Status

Scaffold stage. Directory layout, CI skeleton, and placeholder manifests are
in place; the kernel patches, device-tree overlay, and build scripts are not
yet implemented. See the TODO markers in each file under `patches/`, `dts/`,
`configs/`, and `scripts/`.

## Layout

```
manifests/sources.lock              pinned repo/commit list (TODO: fill in)
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
  runner ([.github/workflows/build.yml](.github/workflows/build.yml)). Builds
  the kernel, U-Boot, and Debian image; runs `dtbs_check`, `dt_binding_check`,
  dtc warnings, and shellcheck. No special hardware required.
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

Once `manifests/sources.lock` is filled in, this pins every source revision
per work order §3 and §9.1.
