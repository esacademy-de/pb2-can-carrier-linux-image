# Carrier device-tree overlay

`k3-am62-pocketbeagle2-can-carrier.dtso`, based on the pinned v6.18.x
`k3-am62-pocketbeagle2.dts` (work order §5.1, manifests/sources.lock).

## Status

Written and verified:

- Pad-ownership matrix built from the base DTS + its
  `k3-am62-pocketbeagle2-pinmux.dtsi` header-pin/ball reference (work
  order §10 step 3) — every carrier signal's IOPAD offset/mode and, where
  the work order calls for one, its companion pad's parked offset/mode,
  is documented inline in the overlay next to the pin it sets.
- RGMII2 pin group and the DP83867 `phy-mode`/`ti,rx-internal-delay`
  pairing cross-checked against linux-stable v6.18's own
  `arch/arm64/boot/dts/ti/k3-am625-sk-common.dtsi`.
- SPI2 mode-0 pin assignment cross-checked against linux-stable v6.18's
  `arch/arm64/boot/dts/ti/k3-am625-sancloud-bbe-2.dts`.
- Compiled with `dtc -@ -W all` via the pinned BeagleBoard-DeviceTrees
  repo's own Makefile (needed for its include paths and CPP flags) —
  zero warnings.
- Applied end-to-end with `fdtoverlay` onto the real compiled base
  `k3-am62-pocketbeagle2.dtb` — merges cleanly, every touched node
  reaches the expected `status`/property values (spot-checked by
  decompiling the merged result).
- `patches/kernel/README.md` covers `dt_binding_check` for the modified
  CAN-transceiver-PHY binding; `scripts/build-image.sh` wires both this
  overlay compile and that check into one script.

One real bug was caught and fixed during that end-to-end testing: a bare
`/ { newnode {...}; };` block at a `/plugin/` file's top level compiles
without error and gets a valid local phandle for in-file references, but
`fdtoverlay`'s runtime apply step only merges actual `fragment@N`/
`__overlay__` structures — an un-wrapped node is silently dropped when
applied to a live base tree. The three PHY nodes and the LED addition now
go through explicit `&{/}` / `&{/leds}` path targets instead (same
pattern BeagleBoard's own overlays use for `&{/chosen}`).

## Scope (work order §4, §5)

- 3× CAN-FD ports: TCAN3413 generic PHY nodes (`ti,tcan3413`, patches/kernel/0001-...) + `main_mcan0`/`mcu_mcan1`/`mcu_mcan0` controllers
- Carrier UART0 as primary console, MAIN_UART6 untouched as secondary — driven by kernel cmdline, not `/chosen/stdout-path` (see the overlay's `&{/chosen}` comment for why, and `configs/uboot.fragment` for the cmdline itself)
- Gigabit Ethernet: CPSW port 2, MDIO0, DP83867 `ethernet-phy@1`, `phy-mode = "rgmii-rxid"`, `ti,rx-internal-delay = DP83867_RGMIIDCTL_2_00_NS`, reset/interrupt GPIOs
- User LED (`carrier:user`, GPIO0_55, active-low) merged into the stock `/leds` node alongside USR LED 1-4
- SPI2 controller only (no spidev / child device in this overlay)
- 13× J3 GPIO lines as unclaimed, no-pull inputs with `J3_<pin>_GPIO<bank>_<n>` libgpiod line names

USB1 host (J5) needs no overlay changes: the stock PB2 DTS already
configures it as required (dr_mode=host, VBUS pins), so touching it here
would violate the "smallest reviewable change" instruction (work order
Appendix C) for no reason.

Later SPI child-device overlays belong in `optional-spi-children/`,
independent and composable — this base overlay must not create a generic
spidev node (work order §5.1, §7.2, §11 SPI-01).

## Known open items (see RELEASE_NOTES.md for the full list)

- `cpsw_port2` has no efuse-backed MAC address hookup (only port1 has
  one in the pinned SoC dtsi) — persistence relies on U-Boot's board
  fixup instead; needs bring-up confirmation (§11 ETH-04).

`main_spi0` (stock, no consumer found in the base DTS) is explicitly
disabled by this overlay: its pinctrl claimed ball A14 (companion of
the Ethernet reset ball GPIO0_40 at the dual-ball P2.29 position) and
ball B13 (the same ball the carrier claims directly as the Ethernet
interrupt, GPIO1_18) — real electrical contention, not just a
documentation gap. See RELEASE_NOTES.md item 3.
- DP83867 `reset-assert-us`/`reset-deassert-us` are conservative
  placeholders pending a datasheet timing check.
