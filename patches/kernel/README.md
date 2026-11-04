# Kernel patches

The two patches required by the work order (§1.1, §6) are written and fully
validated (a third, hardware-driven patch was added after bring-up, see item 3): `git am`-applied on top of the real, fully-patched kernel tree
(pinned base + the recipe's entire K3/RT patch series) and **compiled with
zero errors or warnings** against the real kernel config
(`linux-stable` `v6.18.37`, see `../../manifests/sources.lock`):

1. `0001-phy-can-transceiver-add-TI-TCAN3413-support.patch` — extends the
   generic CAN-transceiver PHY binding
   (`Documentation/devicetree/bindings/phy/ti,tcan104x-can.yaml`) and driver
   (`drivers/phy/phy-can-transceiver.c`) with a first-class `ti,tcan3413`
   compatible. Modeled as a single-channel, STB-only transceiver (no
   software enable pin), reusing `tcan1042_drvdata` since that behavior is
   identical. Adds a binding example (work order §5.3, §6.1).

2. `0002-can-m_can-fix-transceiver-activation-sequencing.patch` — reorders
   `m_can_open()` so the transceiver leaves standby (`phy_power_on()`) only
   after `m_can_start()` has put the M_CAN core in Normal Mode, waits out a
   30–50 µs standby-to-normal transition window, then starts the TX queue.
   Every failure path unwinds in reverse without leaving the PHY active.
   `m_can_close()` already stopped the queue and the M_CAN core before
   asserting standby, so its order was left unchanged (work order §6.2).

3. `0003-net-phy-dp83867-add-ti-led-function-to-select-the-LE.patch` — adds
   an optional `ti,led-function` property (four LEDCR1 source codes: LED_0,
   LED_1, LED_2, LED_GPIO) to `drivers/net/phy/dp83867.c` and its binding
   (`Documentation/devicetree/bindings/net/ti,dp83867.yaml`), and re-applies
   it from `dp83867_config_init()` because the PHY drops the selection on
   every soft reset (including `ip link set eth0 down/up`). The carrier
   overlay uses it for Raspberry-Pi-4/5-style RJ45 LEDs (green = link, blinks
   on activity; orange = 1000BASE-T). Added after hardware bring-up
   (hwbringup/HWBRINGUP_LOG.md §2.3). Verified: compiles with `W=1` without
   warnings, `dt_binding_check` passes with the new property in the binding
   example, `checkpatch` only notes that the binding doc and the driver are in
   one patch (same as patch 0001), and on hardware LEDCR1 reads back `0x65b0`
   after boot and after `ip link set eth0 down/up`. Same `TODO: Signed-off-by`
   marker as the other patches.

## Verification performed

- Applied cleanly with `git am` against a pristine checkout of the pinned
  commit (tag `v6.18.37`, commit `0c503cf3dde2e53614f05261ece12f9d3d4c3c20`).
- A full local build of the pinned kernel recipe (RT + entire K3 patch
  series, minus the one unrelated patch skipped for AM625 — see
  `manifests/sources.lock` [kernel.base]) completed successfully, producing
  a real `Image` + modules + dtbs.
- Both patches then applied cleanly with `git am` on top of *that*
  fully-patched tree (not just the pristine base), and both patched files
  (`drivers/phy/phy-can-transceiver.c`, `drivers/net/can/m_can/m_can.c`)
  compiled with **zero errors or warnings** after merging
  `configs/kernel.fragment` and running `olddefconfig`.
- `dt_binding_check` for the modified `ti,tcan104x-can.yaml` binding passed
  clean (schema processed, example compiled) with the new `ti,tcan3413`
  example in place (work order §6.1, §11 DT-01).

## Before submitting upstream

Each patch carries a `TODO: Signed-off-by` marker instead of a real
`Signed-off-by` trailer. Per work order §6.1, that certification must come
from a human author/maintainer — an AI agent must not fabricate it. Replace
the TODO line with a real `Signed-off-by: Name <email>` before these are
sent upstream.
