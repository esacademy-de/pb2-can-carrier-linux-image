# Carrier device-tree overlay

Target file: `k3-am62-pocketbeagle2-can-carrier.dtso`, based on the
v6.18.x `k3-am62-pocketbeagle2.dts` (work order §5.1).

Not yet written. Before authoring pinctrl, produce the pad-ownership matrix
for every carrier signal and its PB2 companion pad (work order §10 step 3,
§5.2, §Appendix A) — every dual-connected PB2 position must mux exactly one
function and explicitly park the other as a safe, bias-disabled
high-impedance input.

Scope for this overlay (work order §4, §5):

- 3× CAN-FD ports (TCAN3413 generic PHY nodes + M_CAN controllers)
- Carrier UART0 primary console + MAIN_UART6 kept as secondary
- USB1 host (J5) fixed host role
- Gigabit Ethernet: CPSW port 2, MDIO0, DP83867 `ethernet-phy@1`,
  `phy-mode = "rgmii-rxid"`, `ti,rx-internal-delay = DP83867_RGMIIDCTL_2_00_NS`
- User LED (`carrier:user`, GPIO0_55, active-low)
- SPI2 controller only (no spidev / child device in this overlay)
- 13× J3 GPIO lines as unclaimed, no-pull inputs with libgpiod line names

Keep later SPI child-device overlays in `optional-spi-children/`, independent
and composable — this base overlay must not create a generic spidev node
(work order §5.1, §7.2, §11 SPI-01).

Compile with symbols as required, run `dtc` with warnings enabled, and
validate with `dtbs_check` against the matching kernel schema set before
considering this complete (work order §5.1, §11 DT-01).
