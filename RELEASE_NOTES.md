# Release notes

Status: kernel patches and the carrier device-tree overlay are written and
verified (patch application + overlay compile/merge, both against the real
pinned sources — see below); U-Boot build and final Debian rootfs assembly
are not yet wired into `scripts/build-image.sh`; no hardware validation
(work order §11) has been run. This is a software/DT bring-up handoff, not
a flashable release.

## What was verified, and how

- **Kernel patches** (`patches/kernel/*.patch`): generated against and
  applied cleanly with `git am` onto a pristine checkout of linux-stable
  at the exact pinned commit (tag `v6.18.37`,
  `0c503cf3dde2e53614f05261ece12f9d3d4c3c20`). Not yet re-validated
  against a tree with BeagleBoard's own K3/RT patch series already
  applied on top (in progress — `scripts/build-image.sh` does this as
  part of its normal flow; re-run it and check for `git am` conflicts
  before trusting this further).
- **Device-tree overlay** (`dts/k3-am62-pocketbeagle2-can-carrier.dtso`):
  compiled with zero `dtc -W all` warnings via the pinned
  BeagleBoard-DeviceTrees repo's own Makefile, then applied end-to-end
  with `fdtoverlay` onto the real compiled base `.dtb` and spot-checked
  by decompiling the merged result. See `dts/README.md` for the real bug
  this process caught (silently-dropped un-wrapped overlay nodes) and
  how it was fixed.
- **Kernel config fragment** (`configs/kernel.fragment`): the CAN/PHY/
  CPSW symbols most specific to this carrier (`CONFIG_ARCH_K3`,
  `CONFIG_CAN_M_CAN(_PLATFORM)`, `CONFIG_PHY_CAN_TRANSCEIVER`,
  `CONFIG_TI_K3_AM65_CPSW_NUSS`) were checked against the real Kconfig
  files at linux-stable v6.18. The rest of the fragment is the
  conventional TI K3/AM62 set and still needs `merge_config.sh`
  confirmation during a real build (which reports any unknown/dropped
  symbol by name).

## Known limitations and open items

Per work order §1.1 ("no unresolved pin, binding, or driver assumptions
may be hidden"):

1. **U-Boot build and image assembly are not implemented yet.**
   `scripts/build-image.sh` builds the kernel and the device tree but
   stops short of U-Boot (the exact upstream defconfig target for this
   board via `beagleboard/bb-u-boot-pocketbeagle2`'s packaging wasn't
   located — see `configs/uboot.fragment`) and of assembling the final
   Debian image (delegated to `beagleboard/image-builder`, not yet
   wired in). This is the largest remaining piece of work.

2. **Ethernet reset/interrupt pins overlap stock `main_spi0`.** Per work
   order Appendix A, the Ethernet reset GPIO (GPIO1_17) and interrupt
   GPIO (GPIO1_18) sit on the same SoC balls as `main_spi0`'s CLK and D0
   lines. The base PB2 DTS enables `main_spi0` with no visible child
   device/consumer, so this carrier overlay proceeds with the pin
   assignments as the work order explicitly specifies them — but this
   should be confirmed against the schematic/board owner before release,
   since it's a real resource conflict the work order names a resolution
   for without flagging the SPI0 side-effect explicitly.

3. **`cpsw_port2` has no efuse-backed MAC address.** The pinned SoC
   device tree gives `cpsw_port1` a persistent MAC via
   `ti,syscon-efuse = <&cpsw_mac_syscon 0x0>`, but no board in the
   pinned BeagleBoard-DeviceTrees tree uses a second efuse slot for
   port2 — inventing an offset would risk reading undefined efuse
   content. This carrier instead relies on U-Boot's standard K3 board
   fixup (persistent `eth1addr` derived from the SoC's unique ID,
   patched into the DT at boot). Needs a real bring-up check against
   work order §11 ETH-04 (identical MAC across 5 cold boots) once
   U-Boot's persistent environment storage is confirmed enabled.

4. **DP83867 reset timing is a placeholder.** `reset-assert-us = <1000>`
   / `reset-deassert-us = <5000>` are conservative values, not sourced
   from the DP83867E datasheet's exact RESET_N timing table (Appendix B
   link). Confirm/tighten during bring-up.

5. **UART0 `console=ttySN` device name is an unconfirmed guess.**
   `configs/uboot.fragment` derives it from the DT `serial7`/`serial2`
   aliases, but Linux's actual `/dev/ttySN` enumeration for these ports
   hasn't been observed on real hardware. This is exactly the ambiguity
   work order §5.5 asks to test and document rather than assume — do
   that on first boot (`dmesg | grep ttyS`) before considering CON-01/
   CON-02 satisfied. The `earlycon=` half of the cmdline is
   address-based and does not have this problem.

6. **`manifests/sources.lock`** still has two open TODOs:
   `beagleboard/image-builder`'s exact build-time commit (currently
   pinned to a snapshot of `master`, which has no release tags) and the
   Debian snapshot.debian.org timestamp for the rootfs.

7. **Signed-off-by lines are placeholders.** Both kernel patches carry a
   `TODO: Signed-off-by` marker instead of a real DCO trailer — that
   certification must come from a human author before upstream
   submission (work order §6.1); an AI agent must not fabricate it.

## Not yet run at all

Every item in work order §11's validation matrix requires the physical
board and is explicitly out of scope for this stage — see
`tests/README.md` for the full list and which items are automatable once
hardware is available.
