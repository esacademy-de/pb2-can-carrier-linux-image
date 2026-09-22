# Release notes

Status: the kernel patches and the carrier device-tree overlay are fully
built and validated against real, pinned upstream sources — not just
checked for syntax (see below). U-Boot's own source also builds clean.
Final image assembly is actively being wired up by driving
`beagleboard/image-builder` directly (see limitation #1) rather than
re-deriving its U-Boot/TI-firmware packaging pipeline; that work is in
progress and not yet validated end to end. No hardware validation (work
order §11) has been run. This is a software/DT bring-up handoff, not yet
a flashable release.

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
  SPL/u-boot proper. The build only stops at the final `binman`
  packaging step, which needs external TI firmware blobs this repo
  doesn't fetch yet (see limitation #1).

## Known limitations and open items

Per work order §1.1 ("no unresolved pin, binding, or driver assumptions
may be hidden"):

1. **IN PROGRESS — U-Boot's final packaging and Debian image assembly
   via `beagleboard/image-builder`.** U-Boot's own defconfig
   (`am62_pocketbeagle2_a53_defconfig`) is confirmed and builds clean.
   Chased the external-firmware chain as far as it stays carrier-generic:
   - ARM Trusted Firmware's BL31 builds clean from source locally
     (`ARM-software/arm-trusted-firmware` @ `v2.14`,
     `PLAT=k3 TARGET_BOARD=lite SPD=opteed`).
   - TI's DM firmware and SYSFW blobs are fetched from
     `TexasInstruments/ti-linux-firmware` (prebuilt binaries under TI's
     own license, not GPL/BSD like the rest of this repo).
   - Beyond that, U-Boot's SPL/`tiboot3.bin` needs a *signed, combined*
     sysfw+board-config image produced by a third tool
     (`beagleboard/k3-image-gen`), which also needs to know whether this
     specific PB2 unit is GP or HS-FS silicon (changes the signing path).
     This whole chain (SYSFW + k3-image-gen + GP/HS signing) is identical
     for *any* PocketBeagle 2 image, carrier or not.

   That's exactly why we're now wiring in `beagleboard/image-builder`
   directly instead of re-deriving TI's signing pipeline: it already
   solves U-Boot packaging (as a prebuilt `bb-u-boot-pocketbeagle2` .deb
   from BeagleBoard's own apt repo, `debian.beagleboard.org`) and Debian
   rootfs assembly. Real, concrete finding from reading its actual
   scripts (not assumed): BeagleBoard's production images don't compile
   kernel/U-Boot from source at image-build time at all — they
   `apt-get install` prebuilt `.deb` packages into a debootstrapped
   chroot. There is no supported "build kernel from source" mode.

   Current approach, in progress and not yet validated end to end:
   build our own carrier kernel `.deb` (via `make bindeb-pkg` on the
   already-validated patched+configured kernel tree) and serve it as a
   small local flat apt repo inside the chroot, added via
   `image-builder`'s existing `repo_external` extension point, in place
   of BeagleBoard's stock `bbb.io-kernel-6.18-k3`/`bbb.io-headers-6.18-k3`
   packages. A custom image-builder config
   (`configs/pb2-can-carrier-debian-trixie-iot.conf`) and a small hook
   script (`scripts/pb2-carrier-local-repo.sh`, called from a one-line,
   guarded addition to `RootStock-NG.sh` between its debootstrap and
   chroot stages) have been written but not yet committed into this repo
   or run to completion — the kernel `.deb` build and the first full
   pipeline run are both still in flight. Carrier-specific finalization
   (our `.dtbo` + the `FDTOVERLAYS`/console `APPEND` lines in
   `extlinux.conf`) still needs a post-processing step on top of
   `image-builder`'s output; not started.

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

6. **UART0 `console=ttySN` device name is still an unconfirmed guess —
   and my original reasoning for it was wrong.** `configs/uboot.fragment`
   previously derived the guess from the DT `serial7`/`serial2` aliases.
   Checked the actual driver source (`drivers/tty/serial/8250/8250_omap.c`
   and `8250_core.c` at linux-stable v6.18): neither calls
   `of_alias_get_id()` — this platform's 8250 driver does **not** use DT
   aliases to assign `/dev/ttySN` numbers at all. The real mechanism is
   dynamic assignment in kernel probe order, which for two UART nodes
   with no other probe-order dependencies most likely (not guaranteed)
   follows the compiled DTB's node order — but that is still an inference
   from driver behavior, not a fact I can assert without booting real
   hardware. This is exactly the ambiguity work order §5.5 asks to test
   and document rather than assume — do
   that on first boot (`dmesg | grep ttyS`) before considering CON-01/
   CON-02 satisfied. The `earlycon=` half of the cmdline is
   address-based and does not have this problem.

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
