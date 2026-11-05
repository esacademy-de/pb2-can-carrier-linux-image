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

## Hardware bring-up update (2026-11-05)

First bring-up on real hardware (2026-11-04/05) found and fixed:

- **Gigabit Ethernet RX timing**: with the PHY RX internal delay at 2.00 ns
  roughly 35 % of received frames had CRC errors (about 39 % ping loss at 1 Gbit/s).
  A sweep showed a clean window of 2.25-2.75 ns; the overlay now uses 2.50 ns
  (`DP83867_RGMIIDCTL_2_50_NS`). Verified after reboot: 1500 x 1400 B pings, 0 lost, 0 CRC errors.
  The PHY RX-delay straps decode to 2.0 ns, but the Linux driver always overwrites them from DT.
- **PHY interrupt**: `IRQ_TYPE_LEVEL_LOW` made `request_irq` fail on the K3 GPIO controller
  (PHY fell back to polling); now `IRQ_TYPE_EDGE_FALLING`, interrupt counter rises on every link change.
- **RJ45 LEDs**: new kernel patch `0003` (`ti,led-function`) and overlay setting give
  Raspberry-Pi-4/5-style LEDs: green = link, blinking on activity; orange = 1000BASE-T only.
- **Persistent MAC (ETH-04)**: the MAC was random on every boot because `cpsw_port2` (the only
  external port) had no eFuse hookup and the U-Boot fixup the overlay relied on does not happen on
  this board. The overlay now sets `ti,syscon-efuse = <&cpsw_mac_syscon 0x0>` on port 2: the
  interface takes the SoC's factory MAC (44:88:be:d4:c5:ee on the bring-up unit), identical across
  three consecutive boots; the 5x cold-boot check (ETH-04) was checked and confirmed by the owner.
- **SSH on Ethernet from a config file on the SD card**: new `pb2-config.txt` on the FAT partition
  (`ssh=enabled|disabled`, `ssh_password_auth=yes|no`), applied at every boot by
  `pb2-boot-config.service` before `ssh.service`; default SSH enabled, as in the stock image.
  Also fixed: the stock image shipped SSH host keys generated at build time (shared by every unit);
  `assemble-image.sh` now arms BeagleBoard's `/etc/bbb.io/ssh_regenerate` so each unit creates its own
  keys at first boot (one extra automatic reboot). Verified on hardware: disabled -> port 22
  refused from a PC; enabled -> login works; key-only mode with and without an authorized key.
- **Ethernet stayed up after `poweroff`** (RJ45 LEDs on, switch port up): nothing in the shutdown path
  closes `eth0`, so the DP83867 stays powered. `image/pb2-eth-linkdown.service` now runs `ip link set eth0 down`
  during poweroff/halt (not reboot), after systemd-networkd has stopped and before the filesystems are
  unmounted; the kernel then powers the PHY down (phy_detach -> phy_suspend). Installed by `assemble-image.sh`
  (step 5e). Verified on hardware: shutdown order in the console capture, and the user confirmed the link goes down.
- Checked and confirmed by the owner (2026-11-05): the ETH-04 cold-boot check, the card-reader
  hot-plug behaviour and the UART0 login.
- CAN: all external PCAN-USB FD tests pass on all three ports (classic, FD/BRS, shared bus); RT-01 cyclictest max 112 us under load.

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

6. **RESOLVED — console selection (CON-01/CON-02), default reverted to
   MAIN_UART6 (work order D-12, superseding the earlier D-06 UART0-primary
   decision).** The carrier will add a jumper-selectable debug UART
   breakout on J4 (MAIN_UART6 or carrier UART0 to the same FTDI), so the
   software default now matches a stock, unmodified PocketBeagle 2:
   `scripts/assemble-image.sh`/`configs/uboot.fragment` inject
   `console=ttyS2,115200n8 earlycon=ns16550a,mmio32,0x02860000` (MAIN_UART6)
   as the default `append` line. Carrier UART0 is fully implemented and
   confirmed working end-to-end on real hardware, but is now a **manual,
   reboot-time override** — hand-edit `console=ttyS2,115200n8` to
   `console=ttyS7,115200n8` in `/extlinux/extlinux.conf` on the
   already-flashed image (see `configs/uboot.fragment` for the full
   procedure). It is not a separate boot label or build-time image
   variant. Findings below, all confirmed on real hardware via iterative
   UART bring-up (owner-driven, live console captures on both UART6 and
   UART0), remain exactly what the manual override needs to work
   correctly:
   - **`ttyS7` is UART0's real `/dev/ttySN` name**, found via `dmesg |
     grep ttyS` — the original `ttyS0` guess was wrong. Confirmed: the
     8250-omap driver doesn't call `of_alias_get_id()`, so assignment is
     registration-order dependent, not DT-alias based.
   - **`earlycon` must stay on UART6 (`0x02860000`), not UART0.** UART0's
     peripheral clock is never enabled by the stock, unmodified
     `bb-u-boot-pocketbeagle2` firmware. Pointing `earlycon`'s raw MMIO
     probe at UART0 before Linux's clock driver runs hung the CPU outright
     (total silence on both UARTs, no USB enumeration) — reverted once
     confirmed. UART6 is safe because U-Boot already has it clocked.
   - **No baud suffix on `earlycon=`.** Matches BeagleBoard's own stock
     extlinux templates. Per kernel docs, omitting the baud means
     "inherit U-Boot's config"; adding `,115200n8` makes `earlycon`
     actively reprogram the UART against an assumed reference clock,
     which produced garbled output on real hardware.
   - **Only `ttyS7` in `console=` — not both `ttyS7` and `ttyS2`
     together.** Registering both as simultaneous active kernel consoles
     corrupted UART6's output right at the `ttyS7` driver handoff
     (`printk: legacy console [ttyS7] disabled/enabled`), even though the
     UART0 peripheral is fine in isolation — verified by writing test
     strings directly to `/dev/ttyS7` via `stty`/`printf` while UART6 was
     still the sole console, which came through clean. With `ttyS2`
     dropped from `console=`, UART6's log stays clean start to finish and
     `ttyS7` alone carries clean kernel output plus a working login
     prompt, confirmed via a full boot with a TTL adapter on P1.30.
   - **Known, accepted limitation:** with `earlycon` on UART6, the very
     earliest boot messages (pre ~2.6s, before the 8250 driver hands off
     from the earlycon boot console) are visible only on UART6, not on
     UART0. Same class of limitation as the SPL/U-Boot-stage console
     (item 1) — closing it fully would need the same custom-signed
     U-Boot build, not done for the same reasons.
   - **Login getty on BOTH `ttyS2` (MAIN_UART6) and `ttyS7` (carrier
     UART0), confirmed stable on real hardware.** systemd's
     `getty-generator` only creates a login getty for whatever tty is
     named in the kernel's `console=` argument — since only one of
     `ttyS2`/`ttyS7` is ever in `console=` at a time (the exclusivity
     rule above), a naive setup leaves the *other* UART with no login
     prompt at all. `ttyS7` also carries journald's forwarded output
     (item 7) at the same time as its login getty — getting that
     combination working took three rounds (severed journald connection
     → baud-rate garbage → an apparent reboot hang that was later found
     to be an unrelated cause, see item 7/12), but is now confirmed
     stable across multiple reboots and power cycles on real hardware.

7. **RESOLVED (mechanism verified, not yet re-tested on hardware) —
   garbled console output and stray BEL bytes during boot, root-caused
   via a raw byte-level UART capture.** The owner reported console text
   occasionally getting overwritten mid-line and hearing the terminal
   bell several times during boot, always at identical points. Captured
   with a purpose-built Python script (`tests/capture_serial.py`, not
   committed — ad hoc diagnostic tool) that logs the exact bytes
   received, annotating every non-printable byte as an explicit
   `[0xHH]` token instead of letting a terminal interpret it. This
   showed two independent, fully-understood mechanisms, neither a
   hardware fault:
   - **PID1's own status writer racing kernel printk on the same wire.**
     Both write to `/dev/console` (bound to `ttyS2`/MAIN_UART6)
     independently and unsynchronized; on some (not all) status lines,
     a kernel dmesg line lands mid-write inside PID1's own
     carriage-return-based line redraw, splicing the two together —
     exactly the "print over" symptom. **Fix**: `systemd.show_status=no`
     added to the default `console=` line, stopping PID1's own status
     writer from touching `/dev/console` at all. Kernel printk is a
     separate broadcast mechanism, completely unaffected — UART6 stays
     fully verbose. PID1's status stream isn't lost: journald forwards
     its complete stream (kernel messages plus every systemd status
     event) to **UART0 exclusively**, via a new
     `/etc/systemd/journald.conf.d/pb2-carrier-uart0-forward.conf`
     (`ForwardToConsole=yes` + `TTYPath=/dev/ttyS7`) written into the
     rootfs by `scripts/assemble-image.sh`. Deliberately *not* done via
     a second kernel `console=ttyS7` — confirmed above (item 6) to
     corrupt UART6 at the driver handoff. journald forwarding is a
     userspace-only mechanism, independent of kernel console
     registration, so it carries none of that risk. **`systemd.show_status=no`
     confirmed working on real hardware**: UART6 stayed completely free
     of `[ OK ]`/interleaving artifacts across a full fresh boot.
   - **`ttyS7` sharing a getty with journald's forwarding — confirmed
     stable on real hardware, after three rounds to get there.**
     (1) `serial-getty@.service`'s stock `TTYVHangup=yes` performs a
     `vhangup(2)` on the tty as part of starting up, which severed
     journald's already-open `TTYPath` connection the moment the getty
     started, going silent for the rest of boot — fixed: `TTYVHangup=no`
     via a `serial-getty@ttyS7.service.d/override.conf` drop-in (kept,
     for the `ttyS7` instance only). (2) That exposed a second,
     independent problem: nothing configures `ttyS7`'s baud rate before
     journald's own early writes (it isn't a kernel `console=` target,
     so the kernel's console driver never touches it, and `agetty`
     normally would but starts far later than journald) — a raw
     byte-level capture showed a long burst of garbage/NUL bytes until a
     manual `stty` command fixed it — fixed via an `ExecStartPre=` on
     `systemd-journald.service` itself
     (`/etc/systemd/system/systemd-journald.service.d/pb2-carrier-ttyS7-baud.conf`,
     `stty -F /dev/ttyS7 115200 raw -echo opost onlcr` — `opost onlcr`
     added after a follow-up real-hardware finding that plain `raw`
     disables `\n`→`\r\n` translation, producing a cascading/staircase
     display) forcing the baud rate before journald's first write.
     (3) With both of those in place, `reboot`/`poweroff` appeared to
     stall permanently — **initially misdiagnosed** as caused by
     `TTYVHangup=no`, leading to removing the `ttyS7` getty entirely as
     a first response. Further investigation found the real cause was
     unrelated: `bb-usb-gadgets.service` hanging the USB gadget driver
     whenever VBUS is present without a real host to complete
     enumeration (item 12) — confirmed independently of `ttyS7`/getty
     entirely (identical hang on stock, unmodified images with no getty
     changes at all). With `bb-usb-gadgets` disabled by default,
     `TTYVHangup=no` + the `ttyS7` getty was re-tested and **confirmed
     stable across multiple reboots and power cycles on real
     hardware** — both journald's forwarded stream and the login prompt
     work correctly on `ttyS7` at the same time.
   - **The "won't finish booting"/apparent hang with a passive capture
     script is not a bug.** At the very end of boot, `agetty` sends
     `ESC[6n` (a cursor-position query, part of standard terminal
     capability detection) and blocks waiting for a response over the
     same serial line. A real terminal (PuTTY) answers this
     automatically; a read-only capture script cannot, so the board
     waits indefinitely — confirmed in a second capture where the owner
     waited ~44 seconds with nothing happening, then power-cycled the
     board, which is visible in the capture as a clean, normal systemd
     shutdown sequence starting at that exact moment. The board was
     never hung.
   - **The BEL bytes are not corruption.** Both captures show the exact
     same sequence — `ESC!p` (soft terminal reset) + `ESC]104<BEL>`
     (OSC 104, reset ANSI color palette, BEL-terminated per standard
     ECMA-48 convention) + `ESC[?7h` (enable autowrap) — at the same two
     points every boot: once as systemd's console output begins, once
     as the login getty initializes. This is a legitimate, intentional
     control sequence; PuTTY (like many terminals) audibly rings the
     bell for any `0x07` byte regardless of whether it's a real alert or
     a control-sequence terminator, which is a terminal-emulator
     behavior/setting (PuTTY: Terminal → Bell), not a defect in this
     image.

8. **`manifests/sources.lock`** still has two open TODOs:
   `beagleboard/image-builder`'s exact build-time commit (currently
   pinned to a snapshot of `master`, which has no release tags) and the
   Debian snapshot.debian.org timestamp for the rootfs.

9. **Signed-off-by lines are placeholders.** Both kernel patches carry a
   `TODO: Signed-off-by` marker instead of a real DCO trailer — that
   certification must come from a human author before upstream
   submission (work order §6.1); an AI agent must not fabricate it.

10. **PARTIALLY RESOLVED — Ethernet (CPSW/MDIO). Both fixes below were
   tested on the bare PocketBeagle2 module only — the CAN carrier board
   (and its DP83867 PHY chip) has not been attached yet, so this is
   SoC-side/kernel-DT confirmation, not an Ethernet link validation.**
   Nothing here should be read as ETH-01..ETH-05 (work order §11) being
   satisfied; that still needs the carrier board physically attached.
   - **MDIO0/PIN88 pinmux conflict — fix confirmed on the bare module.**
     Another dual-ball companion pad (work order §5.2), same class as the
     two already found in review (`main_spi0`/GPIO1_17 at P2.29,
     `epwm2`/GPIO1_28 at P1.33). Originally seen via `dmesg`:
     `pinctrl-single f4000.pinctrl: pin PIN88 already requested by
     23120000.pwm; cannot claim for 8000000.ethernet`, followed by
     `am65-cpsw-nuss 8000000.ethernet: Error applying setting, reverse
     things back` — CPSW/MDIO0 never finished probing. Traced to source:
     header pin **P2.01** is a dual-ball position — ball **AD24** (offset
     `0x0160`, `MDIO0_MDC`, pinctrl-single index 88 — confirmed
     `0x0160 / 4 = 88`, matching the "PIN88" in the error) and ball
     **B20** (offset `0x01a4`, `ECAP2_IN_APWM_OUT`) are physically the
     same header pin. The base PocketBeagle2 DTS
     (`k3-am62-pocketbeagle2-pinmux.dtsi`) keeps `&ecap2` enabled by
     default with a pinctrl group that claims *both* balls — B20
     actively, AD24 parked as its companion — so its claim on AD24 won
     the probe-order race against `cpsw3g`'s own claim on the same pad.
     Fix: `dts/k3-am62-pocketbeagle2-can-carrier.dtso` now disables
     `&ecap2` (nothing on this carrier uses ECAP2 PWM capture), matching
     the pattern already used for `main_spi0` and `epwm2`. Tested on the
     bare PocketBeagle2 module (no carrier board attached): after
     reflashing the rebuilt `.dtbo`, `dmesg` shows `davinci_mdio` probing
     cleanly with no `pin-88`/`PIN88` errors, and `eth0` appears in
     `ip link show`. This confirms the pinmux/probe-order bug itself is
     fixed at the SoC/kernel level; it does not confirm a working
     Ethernet link, since no PHY chip is physically present yet (see
     below).
   - **RGMII TX delay `dev_warn` — cosmetic, harmless, fix confirmed on
     the bare module.** Separately, `dmesg` showed `am65-cpsw-nuss
     8000000.ethernet: RGMII mode without internal TX delay unsupported;
     please fix your Device Tree`. Traced to
     `drivers/net/ethernet/ti/am65-cpsw-nuss.c`: this specific CPSW MAC
     IP has a **fixed, always-on internal TX delay in RGMII mode that
     isn't board-configurable**; the driver silently remaps a DT
     `phy-mode` of `"rgmii-id"` to `"rgmii-rxid"` internally and only
     *warns* (without changing behavior) when the DT claims no TX delay
     exists anywhere (`"rgmii"` or `"rgmii-rxid"`, our overlay's previous
     setting). Functionally harmless — both cases resolve to the
     identical final `RGMII_RXID` mode the PHY driver sees, and
     upstream's own `k3-am625-sk-common.dtsi` reference board carries the
     exact same `"rgmii-rxid"` setting and would trigger the identical
     warning. Changed `&cpsw_port2`'s `phy-mode` to `"rgmii-id"` anyway,
     for a clean boot log — zero functional change, PHY-side
     `ti,rx-internal-delay` and the unprogrammed PHY TX delay (work order
     §4.3.1) are untouched. Tested on the bare PocketBeagle2 module: the
     warning is gone and `dmesg` shows `configuring for phy/rgmii-rxid
     link mode` — confirming the driver's internal remap to `RGMII_RXID`
     behaves exactly as predicted, identical to the previous setting's
     actual runtime mode.
   - **What is still unverified — the actual Ethernet link.** Both tests
     above were run with the CAN carrier board *not physically attached*
     to the PocketBeagle2. The MDIO bus's only response was a PHY that
     bound as generic (`driver unknown` → `Generic PHY`, not the
     TI-specific `dp83867` driver that `CONFIG_DP83867_PHY=y` already
     enables) and reported `Link is Up - 100Mbps/Full`, which is not
     trustworthy with no real PHY chip answering on the bus — most likely
     a floating-MDIO-line artifact, not a real link. Ethernet cannot be
     considered validated (ETH-01..ETH-05, work order §11) until this is
     re-checked with the carrier board's DP83867 physically attached.

11. **DOCUMENTATION CORRECTION — this board does have a GPU.**
    `manifests/sources.lock [kernel.base]` previously said "AM625/
    PocketBeagle 2 has no such GPU" when explaining why the recipe's
    "imagination" (PowerVR) kernel patch is skipped. That's wrong for
    this unit: PocketBeagle 2 **Rev A1** uses the **AM6254** SoC
    (owner-confirmed), which includes an Imagination PowerVR Rogue
    **AXE-1-16M** GPU — a real, documented hardware upgrade over the
    original AM6232-based Rev A0. The skip decision itself still stands
    for an unrelated reason: the mainline `drm/imagination` PowerVR
    driver has been in-tree since Linux 6.8 (well before this 6.18.37
    base) and needs no patch; the recipe's skipped patch is a separate,
    later backport targeting other/newer chips (AM62A/AM68A/J721S2).
    Confirmed independently: real hardware `dmesg` (captured earlier
    during Ethernet bring-up, before this GPU question came up) already
    shows the mainline driver attempting to probe this exact GPU:
    `powervr fd00000.gpu: Direct firmware load for
    powervr/rogue_33.15.11.3_v1.fw failed with error -2` — `33.15.11.3`
    is the AXE-1-16M's BVNC core ID, confirmed against Mesa's own PowerVR
    driver documentation. Kernel-side probing already works; userspace
    GPU acceleration does not yet (see below) and is not attempted by
    this repo.
    - **RESOLVED — firmware blob added.** `powervr/rogue_33.15.11.3_v1.fw`
      is a real file, confirmed present (via a direct Debian package
      contents search, not guessed) in Debian Trixie's
      `firmware-misc-nonfree` package at exactly
      `/usr/lib/firmware/powervr/rogue_33.15.11.3_v1.fw`. Added
      `firmware-misc-nonfree` to `deb_include` in
      `image-builder/pb2-can-carrier-debian-trixie-iot.conf` (the
      `non-free-firmware` APT component it needs was already enabled in
      `deb_components`) and to `image/package-list.txt` for consistency.
      This silences the real `dmesg` probe failure. **Not yet rebuilt and
      reflashed to confirm on real hardware.**
    - **DECLINED for now — userspace GPU acceleration (Mesa/Vulkan/X11).**
      Owner's actual use case is a plain Xorg/XFCE desktop, accessed
      remotely over RDP, with GPU-accelerated rendering. Researched and
      declined as unrealistic for that specific use case, not attempted:
      - Debian's stock `mesa-vulkan-drivers` (arm64, Trixie) doesn't
        include a PowerVR/imagination driver at all (confirmed via its
        actual package file list: `broadcom, freedreno, gfxstream, lvp,
        nouveau, panfrost, radeon, virtio`) — using it would need
        building Mesa from source with the imagination Vulkan driver
        enabled.
      - This GPU has no native open-source OpenGL driver — Imagination's
        own strategy routes GL through Zink (an OpenGL-over-Vulkan
        translation layer), not a direct path. X11 GPU acceleration
        (`glamor`, which Xorg's `modesetting` driver and `xorgxrdp`'s
        hardware-acceleration path both require) itself needs a working
        GL/EGL implementation with shader support — i.e. it would depend
        on that same Zink translation layer.
      - No evidence found anywhere of anyone combining Zink with
        `glamor`/`xorgxrdp` for *any* GPU — every real, working
        `xorgxrdp`-with-GPU-acceleration report found (Intel, AMD,
        NVIDIA, Qualcomm Adreno) uses a mature, native Mesa GL driver,
        not a Vulkan-via-Zink translation.
      - As of a January 2026 announcement, Imagination's own open-source
        stack for this exact GPU family (AM625/AXE-1-16M, same core as
        this board's AM6254) has made real, credible progress — passing
        Khronos' Vulkan 1.0 conformance suite and running a broader set
        of Vulkan demo applications than before — but that progress is
        specifically about Vulkan/Wayland (Weston), not X11/GLX, and
        Vulkan 1.2 conformance for this core was still pending as of
        that announcement.
      - Separately, XFCE itself doesn't need GPU acceleration to be
        usable, and accessed over RDP the practical bottleneck is
        network encoding of the remote framebuffer, not local rendering
        — so even a working GPU path would likely add fragility for
        little practical benefit in this specific use case.
      - Conclusion: real, working, mainline progress exists for this
        GPU, but only on a Vulkan/Wayland path that doesn't serve this
        use case. Getting X11/glamor/XFCE GPU acceleration working would
        mean building an unprecedented combination (Zink + glamor) with
        no known prior success for any GPU. Not pursued.

12. **RESOLVED (default changed), root cause confirmed on real hardware
    — `bb-usb-gadgets.service` hangs boot/reboot when VBUS is present
    without a real USB host completing enumeration.** Discovered during
    reboot-reliability debugging: on wall-adapter power (no PC on
    USB-C), both cold boot and `sudo reboot` were unreliable —
    sometimes hanging permanently, sometimes booting but never reaching
    a login prompt. Confirmed **not** specific to this carrier image or
    any of its changes: the identical failure occurs on stock,
    unmodified BeagleBoard labels (`4: microSD (debug)`,
    `5: microSD (default)`) with no carrier overlay/config involved at
    all, and with a second, different wall power adapter. Confirmed
    **never** occurs when powered via a PC's USB-C port. Critically,
    also confirmed reproducing when powered through the **P1 header
    pins** — the same pins the CAN carrier board itself uses to power
    the PB2 — so this is not just a USB-C bench-power artifact; it
    affects the actual carrier deployment's own power path. Root-caused
    via a raw boot capture: the hang lands immediately after
    `configfs-gadget.g_multi gadget.0: MAC 44:88:be:d4:c5:f1` — the
    last message before the USB gadget's actual functions/UDC come up
    — consistent with the DWC3 gadget driver's state machine stalling
    when VBUS is asserted (from any non-PC power source through USB-C)
    but no real host ever completes enumeration to unblock it. Confirmed
    fix on real hardware: `sudo systemctl disable --now
    bb-usb-gadgets.service` — boot and reboot became reliable on every
    power source tested (wall adapter, P1 header) after disabling it.
    - **Shipped image default changed to disabled** (owner decision,
      given confirmed reproduction on the carrier's own P1 power path):
      `scripts/assemble-image.sh` now removes the
      `/etc/systemd/system/multi-user.target.wants/bb-usb-gadgets.service`
      enablement symlink as a carrier-finalization step. USB gadget mode
      (NCM network / CDC-ACM serial over USB-C) — an earlier,
      owner-confirmed requirement — remains fully present and working,
      just not started automatically; enable it manually with `sudo
      systemctl enable --now bb-usb-gadgets.service` when actually
      needed (e.g. bench debugging with a PC attached, where a real USB
      host is present to complete enumeration and the hang does not
      occur). Verified the symlink-removal mechanism against the real
      built image (remove, confirm gone, restore, unmount cycle) and
      shellcheck is clean. **Not yet re-tested end-to-end on real
      hardware with a fresh build.**
    - No kernel warning/oops accompanies the hang — it reads as a true
      driver-level stall, not a crash, so `dmesg`-level evidence beyond
      the last-message timestamp hasn't been gathered. A real root-cause
      fix (e.g. a host/VBUS-presence timeout or check in
      `bb-start-usb-gadgets` before starting the gadget) was considered
      but not pursued — disabling by default is sufficient for this
      carrier's actual needs.

## Hardware bring-up status

Owner-driven bring-up on real hardware is underway (not yet complete).
Confirmed so far, via live UART console debugging with the owner:
- **CON-01/CON-02 (UART0 carrier console): RESOLVED**, see item 6 above.
- **Garbled console output / stray BEL bytes: root-caused, fix written,
  not yet re-tested on hardware**, see item 7 above.
- **ETH (Ethernet): PARTIALLY resolved.** MDIO0/PIN88 pinmux conflict
  fix and RGMII TX delay warning fix are both confirmed working on the
  bare PocketBeagle2 module (kernel/DT level only). The CAN carrier
  board with the actual DP83867 PHY has **not** been attached, so no
  real Ethernet link has been tested yet. See item 10 above.
- **Boot/reboot reliability on non-PC power: RESOLVED, shipped-image
  default changed.** See item 12 above — `bb-usb-gadgets.service` hangs
  the USB gadget driver whenever VBUS is present without a real USB
  host to complete enumeration, confirmed on wall-adapter power *and*
  through the carrier's own P1 power pins. Pre-existing on stock
  BeagleBoard images too, not introduced by this carrier's changes.
  Now disabled by default in the shipped image; USB gadget mode remains
  available via manual `systemctl enable`. Not yet re-tested end-to-end
  on real hardware with a fresh build.

Every other item in work order §11's validation matrix (CAN-01..CAN-05,
remaining ETH items, etc.) has not been attempted yet — see
`tests/README.md` for the full list and which items are automatable once
hardware is available.
