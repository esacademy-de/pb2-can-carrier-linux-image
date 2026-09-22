# Release notes

Status: the kernel patches and the carrier device-tree overlay are fully
built and validated against real, pinned upstream sources — not just
checked for syntax (see below). U-Boot's own source also builds clean;
it's blocked only on external TI firmware blobs. Final Debian rootfs
assembly is not yet wired into `scripts/build-image.sh`, and no hardware
validation (work order §11) has been run. This is a software/DT bring-up
handoff, not a flashable release.

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

1. **U-Boot's final packaging and Debian image assembly are not
   implemented yet.** U-Boot's own defconfig
   (`am62_pocketbeagle2_a53_defconfig`) is confirmed and builds clean,
   but the final `binman` packaging step needs external TI firmware
   blobs not yet fetched by this repo: ARM Trusted Firmware (BL31), TI's
   DM firmware from `ti-linux-firmware`, and optionally OP-TEE — see
   https://docs.u-boot.org/en/latest/board/ti/k3.html. Final Debian
   rootfs assembly is delegated to `beagleboard/image-builder`, not yet
   wired in. This is the largest remaining piece of work.

2. **One kernel recipe patch is deliberately skipped.** The recipe's
   own "imagination" backport (Imagination PowerVR GPU driver, from
   v6.19.14) doesn't apply to the 6.18.37 base this build pins to for
   PREEMPT_RT, and targets a GPU AM625/PocketBeagle 2 doesn't have
   (that's AM62A/AM68A/J721S2). `scripts/build-image.sh` skips just that
   one `patch.sh` entry — confirmed by a real full kernel build
   completing successfully with every other K3/RT patch applied. See
   `manifests/sources.lock` [kernel.base].

3. **Ethernet reset/interrupt pins overlap stock `main_spi0`.** Per work
   order Appendix A, the Ethernet reset GPIO (GPIO1_17) and interrupt
   GPIO (GPIO1_18) sit on the same SoC balls as `main_spi0`'s CLK and D0
   lines. The base PB2 DTS enables `main_spi0` with no visible child
   device/consumer, so this carrier overlay proceeds with the pin
   assignments as the work order explicitly specifies them — but this
   should be confirmed against the schematic/board owner before release,
   since it's a real resource conflict the work order names a resolution
   for without flagging the SPI0 side-effect explicitly.

4. **`cpsw_port2` has no efuse-backed MAC address.** The pinned SoC
   device tree gives `cpsw_port1` a persistent MAC via
   `ti,syscon-efuse = <&cpsw_mac_syscon 0x0>`, but no board in the
   pinned BeagleBoard-DeviceTrees tree uses a second efuse slot for
   port2 — inventing an offset would risk reading undefined efuse
   content. This carrier instead relies on U-Boot's standard K3 board
   fixup (persistent `eth1addr` derived from the SoC's unique ID,
   patched into the DT at boot). Needs a real bring-up check against
   work order §11 ETH-04 (identical MAC across 5 cold boots) once
   U-Boot's persistent environment storage is confirmed enabled.

5. **DP83867 reset timing is a placeholder.** `reset-assert-us = <1000>`
   / `reset-deassert-us = <5000>` are conservative values, not sourced
   from the DP83867E datasheet's exact RESET_N timing table (Appendix B
   link). Confirm/tighten during bring-up.

6. **UART0 `console=ttySN` device name is an unconfirmed guess.**
   `configs/uboot.fragment` derives it from the DT `serial7`/`serial2`
   aliases, but Linux's actual `/dev/ttySN` enumeration for these ports
   hasn't been observed on real hardware. This is exactly the ambiguity
   work order §5.5 asks to test and document rather than assume — do
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
