# Release notes

Status: **a complete, flashable PB2 CAN Carrier microSD image has been
built and produced**, end to end, on real infrastructure — not just the
individual pieces validated in isolation. `scripts/assemble-image.sh`
automates the full chain: our patched/configured kernel → packaged as a
real `.deb` → installed into a real `beagleboard/image-builder` rootfs
build (debootstrap + chroot, in place of BeagleBoard's stock kernel
package) → turned into a real bootable `.img` by BeagleBoard's own
`setup_sdcard.sh` (real, already-signed U-Boot/TI firmware included) →
our carrier device-tree overlay and extlinux boot entry injected as a
carrier-specific finalization step on top. See "What was verified, and
how" below for exactly what that first run produced. No hardware
validation (work order §11) has been run yet — that's the next and last
remaining step, and it's yours to do.

## What was verified, and how

All of the following was done against real local builds (WSL, real
aarch64/arm cross toolchains), not just read/reasoned about:

- **Full kernel build succeeded**: the pinned recipe
  (`RobertCNelson/arm64-multiplatform` @ `v6.18.x-arm64-k3`) built
  linux-stable `v6.18.37` with PREEMPT_RT and its entire K3 patch series
  (minus the one skipped Imagination-GPU backport — see limitation #2
  below) all the way to a deployable `Image` (47 MB), a modules archive,
  and a dtbs archive. This proves the RT/version-pin override and the
  imagination-patch skip actually work together, not just in theory.
- **Both kernel patches** (`patches/kernel/*.patch`): applied cleanly
  with `git am` on top of that *fully-patched* tree (not just a pristine
  base checkout), and both patched files
  (`drivers/phy/phy-can-transceiver.c`, `drivers/net/can/m_can/m_can.c`)
  **compiled with zero errors or warnings** against the real kernel
  config.
- **Kernel config fragment** (`configs/kernel.fragment`): merged with the
  real `scripts/kconfig/merge_config.sh` into the working `.config`, then
  `olddefconfig`'d — every symbol resolved to the intended value
  (spot-checked `CONFIG_ARCH_K3`, `CONFIG_CAN`, `CONFIG_CAN_M_CAN`,
  `CONFIG_PHY_CAN_TRANSCEIVER` directly in the resulting `.config`).
- **`dt_binding_check`** for the modified CAN-transceiver-PHY binding
  passed clean (schema processed, example compiled) with both the
  `ti,tcan3413` compatible and its new binding example in place.
- **Device-tree overlay** (`dts/k3-am62-pocketbeagle2-can-carrier.dtso`):
  compiled with zero `dtc -W all` warnings via the pinned
  BeagleBoard-DeviceTrees repo's own Makefile, then applied end-to-end
  with `fdtoverlay` onto the real compiled base `.dtb` and spot-checked
  by decompiling the merged result. See `dts/README.md` for the real bug
  this process caught (silently-dropped un-wrapped overlay nodes) and
  how it was fixed.
- **U-Boot**: configured with the real, confirmed defconfig
  (`am62_pocketbeagle2_a53_defconfig`) plus `configs/uboot.fragment`
  merged in, and built — U-Boot's own sources compile clean through
  SPL/u-boot proper (the from-source build stops at final `binman`
  packaging, which needs TI-signed blobs — see limitation #1 for how
  that's actually solved, without needing this from-source build at all).
- **A complete, flashable `.img` was produced**: our kernel packaged as a
  real `.deb`, installed into a real `beagleboard/image-builder`
  debootstrap+chroot rootfs build via its `repo_external` mechanism
  (confirmed in the resulting `dpkg-list.txt`: our
  `linux-image-6.18.37-arm64-k3-r56` is there, BeagleBoard's stock
  `bbb.io-kernel-6.18-k3` is not), turned into a bootable image with
  BeagleBoard's own `setup_sdcard.sh --dtb pocketbeagle2-swap`, then our
  carrier `.dtbo` and a new default extlinux boot entry injected by
  mounting the image's boot partition directly. Every stock boot label
  (including the TechLab cape ones) was left intact alongside it. See
  `image-builder/README.md` for the real findings this uncovered
  (BeagleBoard ships prebuilt, already-signed U-Boot firmware; the real
  `fdtoverlays` syntax and boot-partition layout; the confirmed real
  `ttyS2` console device for MAIN_UART6; a missing `tree` host dependency
  in `image-builder`'s own `install_dependencies.sh`).

## Known limitations and open items

Per work order §1.1 ("no unresolved pin, binding, or driver assumptions
may be hidden"):

1. **RESOLVED — U-Boot's final packaging and Debian image assembly via
   `beagleboard/image-builder`.** U-Boot's own defconfig
   (`am62_pocketbeagle2_a53_defconfig`) builds clean from source, but
   getting from there to a signed, bootable `tiboot3.bin`/`tispl.bin`
   needs TI's SYSFW + `k3-image-gen` + GP-vs-HS signing — identical
   plumbing for *any* PocketBeagle 2 image, carrier or not. Rather than
   re-derive that, this repo now drives `beagleboard/image-builder`
   directly (real, concrete finding: BeagleBoard's production images
   `apt-get install` prebuilt `.deb` packages into a debootstrapped
   chroot rather than compiling kernel/U-Boot from source at all — there
   is no supported "build from source" mode).

   `scripts/assemble-image.sh` automates the full chain and has been run
   successfully end to end:
   1. Packages the already-patched/configured kernel as a real `.deb`
      (`make bindeb-pkg`).
   2. Serves it as a small local flat apt repo inside
      `beagleboard/image-builder`'s chroot, via its existing
      `repo_external` extension point
      (`image-builder/pb2-carrier-local-repo.sh`, hooked in by a 4-line
      patch to `RootStock-NG.sh`,
      `image-builder/rootstock-ng-carrier-hook.patch`), in place of the
      stock `bbb.io-kernel-6.18-k3`/`bbb.io-headers-6.18-k3` packages.
      Confirmed in the resulting rootfs's `dpkg-list.txt`: our kernel is
      there, the stock one is not.
   3. Runs the real `beagleboard/image-builder` pipeline
      (`image-builder/pb2-can-carrier-debian-trixie-iot.conf`, a trimmed
      copy of BeagleBoard's own IoT config) — real debootstrap + chroot,
      under QEMU arm64 emulation.
   4. Produces a real bootable `.img` with BeagleBoard's own
      `setup_sdcard.sh --dtb pocketbeagle2-swap` — this pulls in the
      **real, already TI-signed** `bb-u-boot-pocketbeagle2` firmware
      (`tiboot3.bin`, `tispl.bin`, `u-boot.img`, `bl31.bin`), fully
      solving the signing gap without touching `k3-image-gen` at all.
   5. Mounts the image's FAT boot partition directly and injects the
      carrier `.dtbo` plus a new default extlinux label with the
      `fdtoverlays` line and console `append` arguments — every stock
      boot label (including BeagleBoard's TechLab cape ones) is left
      intact alongside it for fallback/debug.

   See `image-builder/README.md` for the full real findings this
   uncovered — including two corrections to earlier, unverified
   assumptions in `configs/uboot.fragment` (the real `fdtoverlays` syntax
   is lowercase and boot-partition-relative, not the uppercase
   `FDTOVERLAYS`/`/boot/dtbs/<ver>/` path guessed earlier; MAIN_UART6's
   real, shipped console device is confirmed `ttyS2`, not the `ttyS1`
   reasoned from compiled-DTB node order) — and a missing `tree` host
   dependency in `image-builder`'s own `install_dependencies.sh` that
   caused the first run to fail one step from the end (recovered without
   redoing the ~1 hour of debootstrap+chroot work by completing the
   remaining tail manually, then fixed properly in
   `scripts/assemble-image.sh` for future runs).

2. **One kernel recipe patch is deliberately skipped.** The recipe's
   own "imagination" backport (Imagination PowerVR GPU driver, from
   v6.19.14) doesn't apply to the 6.18.37 base this build pins to for
   PREEMPT_RT, and targets a GPU AM625/PocketBeagle 2 doesn't have
   (that's AM62A/AM68A/J721S2). `scripts/build-image.sh` skips just that
   one `patch.sh` entry — confirmed by a real full kernel build
   completing successfully with every other K3/RT patch applied. See
   `manifests/sources.lock` [kernel.base].

3. **RESOLVED — Ethernet reset/interrupt pins vs stock `main_spi0`.**
   `main_spi0`'s own pinctrl claims ball A14 (SPI0_CLK, the companion of
   GPIO0_40 at the dual-ball P2.29 position) and ball B13 (SPI0_D0, the
   same ball the carrier claims directly as GPIO1_18 for the Ethernet
   interrupt). Leaving `main_spi0` enabled meant it would keep driving
   A14 as an active SPI clock in direct electrical contention with
   GPIO0_40 on the same physical header pin, and would contend with the
   carrier's own claim on B13 — a real bug, not just a documentation
   gap, caught in review. Fixed: the overlay now explicitly disables
   `main_spi0` and adds an explicit high-impedance park for GPIO1_17
   (ball A14), matching the pattern already used for every other
   dual-ball companion. No consumer of `main_spi0` was found anywhere in
   the base PB2 DTS tree. Verified: the merged tree shows
   `main_spi0`'s `status = "disabled"` and the new park group correctly
   included in `cpsw3g`'s `pinctrl-0`.

4. **CONFIRMED BY OWNER — `cpsw_port2` MAC address via U-Boot fixup.**
   `cpsw_port2` has no efuse-backed MAC address slot in the pinned SoC
   device tree (only `cpsw_port1` has one, via
   `ti,syscon-efuse = <&cpsw_mac_syscon 0x0>` — no board in the pinned
   BeagleBoard-DeviceTrees tree uses a second efuse slot for port2, and
   inventing an offset would risk reading undefined efuse content).
   Board owner confirmed keeping the alternative already implemented:
   U-Boot's standard K3 board fixup (persistent `eth1addr` derived from
   the SoC's unique ID, patched into the DT at boot) rather than a
   device-tree-level MAC or a fixed/baked-in address. Design decision
   closed; still needs a real bring-up check against work order §11
   ETH-04 (identical MAC across 5 cold boots) once U-Boot's persistent
   environment storage is confirmed enabled.

5. **RESOLVED — DP83867 reset timing.** Confirmed against the real
   DP83867E datasheet (TI SNLS504G, Appendix B link), §6.7 Reset Timing:
   RESET_N minimum assert pulse (T4) = 1 µs; settling time after
   deassert before MDIO register access (T1) = 195 µs nominal.
   `reset-assert-us = <1000>` / `reset-deassert-us = <1000>` both carry
   a >5x safety margin over those figures.

6. **PARTIALLY RESOLVED — UART0 `console=ttySN` device name.**
   MAIN_UART6's real, shipped console device is now confirmed: `ttyS2` —
   extracted directly from BeagleBoard's own real
   `microsd-extlinux-w-swap.conf` (inside the `bb-u-boot-pocketbeagle2`
   package), not reasoned or guessed. The carrier's own extlinux entry
   (injected by `scripts/assemble-image.sh`) now uses that confirmed
   value for the fallback console. UART0's number is still unconfirmed —
   no stock reference enables it, so there's nothing real to extract it
   from — and my original reasoning for guessing it (DT `serial7`/`serial2`
   aliases) was wrong: the actual 8250-omap driver doesn't call
   `of_alias_get_id()`, so `/dev/ttySN` assignment is dynamic probe-order,
   not alias-based. The injected boot entry hedges instead of guessing
   confidently: `console=ttyS0,115200n8 console=ttyS2,115200n8
   earlycon=ns16550a,mmio32,0x02800000,115200n8` — tries `ttyS0` for
   UART0, keeps the confirmed `ttyS2` (UART6) as a working fallback, and
   the address-based `earlycon` shows very-early kernel messages on the
   real UART0 hardware regardless of which `ttySN` it ends up as. This is
   exactly the ambiguity work order §5.5 asks to test and document rather
   than assume — confirm the real mapping via `dmesg | grep ttyS` on
   first boot before considering CON-01/CON-02 satisfied, and correct the
   `ttyS0` guess in the extlinux entry if it's wrong.

7. **`manifests/sources.lock`** still has two open TODOs:
   `beagleboard/image-builder`'s exact build-time commit (currently
   pinned to a snapshot of `master`, which has no release tags) and the
   Debian snapshot.debian.org timestamp for the rootfs.

8. **Signed-off-by lines are placeholders.** Both kernel patches carry a
   `TODO: Signed-off-by` marker instead of a real DCO trailer — that
   certification must come from a human author before upstream
   submission (work order §6.1); an AI agent must not fabricate it.

## Not yet run at all

Every item in work order §11's validation matrix requires the physical
board and is explicitly out of scope for this stage — see
`tests/README.md` for the full list and which items are automatable once
hardware is available.
