# Validation matrix

One script per test ID from work order §11, invoked by
`scripts/flash-and-verify.sh` on the self-hosted `pb2-bench` runner unless
noted otherwise. None are implemented yet.

| ID | Test | Automatable in CI? |
|---|---|---|
| BOOT-01 | Ten consecutive cold boots reach multi-user.target | yes |
| CON-01 | Carrier UART0 console (SPL/U-Boot/kernel/login) | yes |
| CON-02 | Secondary MAIN_UART6 console | yes |
| CAN-01 | Reset safety (STB stays high until controller ready) | no — needs scope/logic analyzer, manual capture |
| CAN-02 | Interface lifecycle, 100 cycles | yes |
| CAN-03 | Nominal CAN FD (500 kbit/s / 2 Mbit/s) | yes |
| CAN-04 | High-rate CAN FD (5 Mbit/s data phase + rate cap) | yes |
| CAN-05 | Concurrent 3-port operation under load | yes |
| ETH-01 | PHY discovery at MDIO address 1 | yes |
| ETH-02 | RGMII timing register readback | yes |
| ETH-03 | Ethernet link/data at 10/100/1000 | yes (equipment permitting) |
| ETH-04 | MAC identity stable across 5 cold boots | yes |
| ETH-05 | RJ45 LED states | no — needs photo/video evidence |
| USB-01 | J5 host enumeration/VBUS | yes |
| USB-02 | PB2 USB0 stock OTG behavior | yes |
| LED-01 | User LED default-off, active-low, no epwm2 conflict | yes |
| SPI-01 | SPI2 controller only, no spidev/child in base DT | yes |
| GPIO-01 | J3 line inventory via gpioinfo | yes |
| GPIO-02 | J3 electrical exercise (request/toggle/release) | yes, with fixture |
| PB2-01 | Stock PB2 function smoke checklist | yes |
| RT-01 | PREEMPT_RT + cyclictest under load | yes |
| DT-01 | dt_binding_check / dtbs_check / dtc warnings | yes — runs in build.yml, not hardware |
| REP-01 | Clean rebuild from pinned inputs | yes — runs in build.yml, not hardware |

Minimum diagnostic capture per run (work order §11.1): `uname -a`,
`/sys/kernel/realtime`, `/proc/cmdline`, serial-getty unit status, `dmesg`
(err/warn), live devicetree dump, `ip -details link show` (+ ethtool +
PHY register dump), CAN link/candump/cangen logs for all three channels,
`gpioinfo`/`gpiodetect`, `lsusb -t`, full journal from cold boot, and the
full cyclictest invocation/result.
