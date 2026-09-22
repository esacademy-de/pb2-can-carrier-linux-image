# Kernel patches

Both patches required by the work order (§1.1, §6) are written and verified
to apply cleanly with `git am` against the pinned kernel commit
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

## Verification performed

- Both patches were generated against and `git am`-applied cleanly onto a
  pristine checkout of `linux-stable` at the exact pinned commit
  (tag `v6.18.37`, commit `0c503cf3dde2e53614f05261ece12f9d3d4c3c20`).
- `dt_binding_check` / `dtbs_check` against the modified binding still need
  to run as part of the full kernel build (work order §6.1, §11 DT-01) —
  see `scripts/build-image.sh`.

## Before submitting upstream

Each patch carries a `TODO: Signed-off-by` marker instead of a real
`Signed-off-by` trailer. Per work order §6.1, that certification must come
from a human author/maintainer — an AI agent must not fabricate it. Replace
the TODO line with a real `Signed-off-by: Name <email>` before these are
sent upstream.
