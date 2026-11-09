# Optional SPI child-device overlays

J1/J2 are parallel copies of the same SPI2 bus and the same CS0 — not
independent buses or independent chip selects (work order §4.5). The base
carrier overlay enables the SPI2 controller only; child-device selection
belongs here, in separate, composable overlays layered on top of it.

| Overlay | What it adds |
|---|---|
| `k3-am62-pocketbeagle2-can-carrier-spidev.dtso` | one generic `/dev/spidev2.0` (SPI2 = bus 2, chip select 0) for user-space SPI access |

The compiled `.dtbo` files are part of the `pb2-can-carrier-support`
package and land in `/boot/firmware/overlays/`. They are **not** active by
default. On the board:

```
sudo pb2-overlay list
sudo pb2-overlay enable spidev     # takes effect at the next boot
sudo reboot
ls -l /dev/spidev2.0
sudo pb2-overlay disable spidev
```

The device is accessible to the `spi` group (the `debian` user is a member
after its next login; other users: `sudo adduser <name> spi`).

Pins (SPI2, mode 0 function): P1.06 CS0, P1.08 CLK, P1.10 MISO, P1.12 MOSI.
Loopback test without any device: connect P1.12 (MOSI) to P1.10 (MISO) and
run `echo hello | spi-pipe -d /dev/spidev2.0 -s 1000000 | xxd` (package
`spi-tools`); the output must be the same bytes that were sent. Without the
wire MISO reads all zeros. Python: `python3-spidev` (`spidev.SpiDev()`,
`open(2, 0)`) or `python3-periphery`; the controller has no internal
loopback mode (`SPI_LOOP` is rejected).

Further child overlays follow the same naming scheme,
`k3-am62-pocketbeagle2-can-carrier-<name>.dtso`, and are then switched with
`pb2-overlay enable <name>` automatically.
