# image-builder integration

Real, validated recipe for assembling a flashable PB2 CAN Carrier microSD
`.img` on top of `beagleboard/image-builder`, instead of re-deriving TI's
K3 firmware-signing pipeline ourselves (see `manifests/sources.lock`
`[firmware]`). This has been run end to end once and produced a working
image; `scripts/assemble-image.sh` automates it.

## What's here

- `rootstock-ng-carrier-hook.patch` — a 4-line patch to
  `image-builder/RootStock-NG.sh` adding one guarded hook call between its
  debootstrap and chroot stages. No-op for anyone using an unpatched
  `image-builder` checkout (the hook only fires if the script below is
  present).
- `pb2-carrier-local-repo.sh` — copy to `image-builder/scripts/`. Populates
  a small local flat apt repo (`/opt/pb2-carrier-repo` inside the target
  rootfs) from our own carrier kernel `.deb` (built from
  `patches/kernel/*.patch` + `configs/kernel.fragment` against the pinned
  base — see `manifests/sources.lock`), so `image-builder`'s existing
  `repo_external` mechanism can install it.
- `pb2-can-carrier-debian-trixie-iot.conf` — copy to
  `image-builder/configs/`. Derived from BeagleBoard's own
  `bb.org-debian-trixie-iot-v6.18-k3-arm64.conf`, trimmed of the heavy
  generic extras (docker, cockpit, code-server, other boards' u-boot
  packages) for a faster validation build, and pointed at our local kernel
  repo via `repo_external` in place of the stock
  `bbb.io-kernel-6.18-k3`/`bbb.io-headers-6.18-k3` packages. Reconcile with
  the full IoT package set before a real release build.

## Real findings from actually running this

- BeagleBoard's production images do **not** compile kernel/U-Boot from
  source at image-build time. `image-builder` installs prebuilt `.deb`
  packages from `debian.beagleboard.org`/`repos.rcn-ee.com`. There is no
  supported "build from source" mode — hence this integration instead of
  a from-scratch pipeline.
- The `bb-u-boot-pocketbeagle2` package ships the **real, already
  TI-signed** firmware: `tiboot3.bin`, `tispl.bin`, `u-boot.img`,
  `bl31.bin`. This solves the entire SYSFW/`k3-image-gen`/GP-vs-HS signing
  gap noted in `manifests/sources.lock` `[firmware]` — no need to chase it
  ourselves.
- `make bindeb-pkg` (generic upstream kernel packaging, what
  `scripts/build-image.sh`/this integration uses) places dtbs under
  `/usr/lib/linux-image-<version>/`, not `/boot/dtbs/<version>/`. Doesn't
  matter in practice: the real extlinux template uses `fdtdir /` (flat
  boot-partition root), and `setup_sdcard.sh` copies what it needs into
  place regardless of where the package put it.
- The real PocketBeagle 2 `extlinux.conf` (from
  `bb-u-boot-pocketbeagle2`'s `microsd-extlinux-w-swap.conf`, confirmed by
  extracting the actual package) uses lowercase `fdtoverlays
  /overlays/<file>.dtbo` (relative to the FAT boot-partition root), not
  the uppercase `FDTOVERLAYS` guessed earlier from a disabled example
  comment in `setup_sdcard.sh`. `configs/uboot.fragment`'s earlier
  guidance using `FDTOVERLAYS` was corrected.
- The real, shipped stock console for MAIN_UART6 is confirmed as
  **`ttyS2`** (from that same real template) — not `ttyS1` as reasoned
  from compiled-DTB node order. UART0's number is still unconfirmed (nothing
  in any stock reference enables it), so the carrier's own extlinux entry
  hedges: `console=ttyS0,115200n8 console=ttyS2,115200n8
  earlycon=ns16550a,mmio32,0x02800000,115200n8` — tries the reasoned guess
  for UART0, keeps the confirmed-working UART6 as a fallback, and the
  address-based `earlycon` shows very-early kernel messages on UART0
  regardless of which `ttySN` it ends up as. Still needs a real `dmesg`
  check on hardware (work order §5.5).
- The exact, authoritative build+flash commands (confirmed against
  BeagleBoard's own CI, `ci/daily-debian-arm64-13-iot-v6.18-k3.sh`):
  ```
  ./RootStock-NG.sh -c pb2-can-carrier-debian-trixie-iot
  source .project
  cd ./deploy/${export_filename}/
  sudo ./setup_sdcard.sh --img-4gb pocketbeagle2-${export_filename} --dtb pocketbeagle2-swap
  ```
- The default account baked in by `pb2-can-carrier-debian-trixie-iot.conf`
  is `debian` / `temppwd` (root login disabled) — same mechanism
  BeagleBoard's own stock images use. It can be overridden without
  rebuilding the image: `sysconf.txt` on the FAT boot partition (also
  editable via BeagleBoard's own Imaging Utility, `bb-beagle-flasher`) is
  read by a first-boot script baked into the rootfs.
- **Known host dependency gap**: `image-builder`'s own
  `scripts/install_dependencies.sh` does not install `tree`, which
  `scripts/chroot.sh`'s final packaging step calls unconditionally under
  `set -e` — a fresh build host without `tree` already installed will fail
  right at the end, after debootstrap and all package installs have
  already completed. `scripts/assemble-image.sh` installs it explicitly to
  avoid this.

## Carrier-specific finalization (not automated by image-builder itself)

`setup_sdcard.sh` produces a stock PocketBeagle 2 image with none of the
carrier-specific device-tree overlay wired in — that's carrier-specific,
not something BeagleBoard's generic tooling should know about. After
`setup_sdcard.sh` completes, `scripts/assemble-image.sh` mounts the
produced image's FAT boot partition and:

1. Copies `dts/k3-am62-pocketbeagle2-can-carrier.dtbo` (built from
   `dts/k3-am62-pocketbeagle2-can-carrier.dtso`) into `/overlays/`.
2. Adds a new `PB2 CAN Carrier` label to `/extlinux/extlinux.conf`, sets
   it as the default, and adds the `fdtoverlays` line plus the console
   `append` arguments above — while leaving every stock label (including
   the plain `microSD (default)` and the TechLab cape ones) intact for
   fallback/debug.
