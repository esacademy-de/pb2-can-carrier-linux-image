# Kernel patches

Two patches are required by the work order (§1.1, §6):

1. `0001-phy-can-transceiver-add-ti-tcan3413.patch` — extend the generic
   CAN-transceiver PHY binding/driver with a first-class `ti,tcan3413`
   compatible (work order §5.3, §6.1). Not yet written.

2. `0002-can-m_can-fix-transceiver-activation-sequencing.patch` — change the
   M_CAN open/start/close sequencing so the TCAN3413 leaves standby only
   after the controller is initialized and ready, and re-enters standby
   before the controller stops (work order §6.2). Not yet written.

Both patches must be prepared in upstreamable form with focused commit
messages. `Signed-off-by` must be supplied by the implementing
organization/author — never fabricated by an AI agent (work order §6.1).

Run `dt_binding_check` and `dtbs_check` against the modified binding before
considering patch 1 complete (work order §6.1, §11 DT-01).
