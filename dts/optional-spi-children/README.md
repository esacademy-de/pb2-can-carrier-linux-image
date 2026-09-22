# Optional SPI child-device overlays

J1/J2 are parallel copies of the same SPI2 bus and the same CS0 — not
independent buses or independent chip selects (work order §4.5). The base
carrier overlay enables the SPI2 controller only; child-device selection
belongs here, in separate, composable overlays layered on top of it.

No child overlays exist yet.
