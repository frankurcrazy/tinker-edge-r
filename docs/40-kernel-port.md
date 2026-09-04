# Kernel: the Tinker Edge R port to Linux 6.1

## Trees

| tree | branch / commit | role |
|---|---|---|
| `frankurcrazy/TB-RK3399ProD-Kernel-6.1` | `develop-6.1-rt45` (6.1.118 + PREEMPT_RT patch-6.1.119-rt45, Rockchip vendor drivers, Toybrick RK3399ProD port with NPU support) | base |
| same repository | **`tinker-edge-r`** = base + `arm64: dts: rockchip: add ASUS Tinker Edge R (RK3399Pro)` | what the manifest builds |
| `frankurcrazy/tinker-edge-r-debian-kernel` | `linux4.4-rk3399pro` (ASUS's official 4.4.194) | source of truth for board wiring, reference only |

The port is a single commit adding three files under `arch/arm64/boot/dts/rockchip/`:

* `rk3399pro-tinker-edge-r.dtsi` - the board
* `rk3399pro-tinker-edge-r.dts` - default DTB (HDMI-RX bridge on CSI0)
* `rk3399pro-tinker-edge-r-hdmirx-csi1.dts` - variant with the bridge on CSI1

plus the Makefile entries.  The same change is kept as `patches/kernel/0001-*.patch`
and as a staging copy in `kernel/` of the build repository; the kernel branch is canonical.

The kernel is built with `rockchip_linux_defconfig` (the Toybrick maintainer's config,
`CONFIG_PREEMPT_RT=y`) plus three fragments from `configs/kernel/`:

| fragment | purpose |
|---|---|
| `tinker-edge-r.config` | board: RTL8822CE PCIe Wi-Fi (`rtw88_8822ce`) + USB Bluetooth (`btrtl`), no built-in `CONFIG_EXTRA_FIRMWARE` (the Toybrick tree references blobs that are not in git), IMU/compass/EEPROM drivers, GPIO sysfs + debugfs for the NPU tools, cgroups/namespaces/netfilter/overlayfs and USB class drivers a normal Ubuntu expects |
| `usb-gadget-typec.config` | Type-C class (TCPM, FUSB302, DP altmode), dwc3 dual role, `USB_ROLE_SWITCH`, configfs gadget with every function, legacy `g_*` gadgets as modules |
| `media-hdmi-rx.config` | vendor rkisp1 + MIPI D-PHY RX + vendor `tc35874x` bridge driver (TC358743/TC358749), RPi camera sensors as modules, CEC |

`scripts/stage-kernel.sh` merges them with `merge_config.sh`, runs `olddefconfig` and
fails if any `=y`/`=m` line of a fragment is missing from the result.

## Method

1. Read ASUS's `rk3399pro-tinker_edge_r.dts` (4.4) node by node: it is
   `rk3399pro-evb-v11-linux` plus ASUS changes (regulator voltages, GPIO
   assignments, Wi-Fi/BT enables, LEDs, cameras, display accessories).
2. Take the 6.1 tree's own RK3399Pro files as templates for 6.1 bindings:
   `rk3399pro-toybrick*.dtsi` (what the maintainer boots, including the NPU-over-USB
   arrangement) and `rk3399pro-evb-v11-linux.dts` (Type-C with TCPM).
3. Carry ASUS's board facts into the 6.1 syntax; drop ASUS-specific properties that no
   6.1 driver reads; keep everything else as close to the tested Toybrick/EVB files as possible.
4. Verify the facts against the schematic block diagram and the live ASUS Debian 10 board
   (see [95-board-notes.md](95-board-notes.md)).

## Node-by-node mapping

| block | 4.4 (ASUS) | 6.1 (this port) | notes |
|---|---|---|---|
| root `compatible` | `rockchip,rk3399pro-evb-v11-linux` | `asus,tinker-edge-r`, `rockchip,rk3399pro-tinker-edge-r`, `rockchip,rk3399pro` | ASUS's NPU scripts only look for `rk3399pro` |
| includes | `rk3399pro.dtsi`, `rk3399-linux.dtsi`, `rk3399-opp.dtsi`, `rk3399-vop-clk-set.dtsi` | `rk3399pro.dtsi`, `rk3399-linux.dtsi`, `rk3399-opp.dtsi` | `rk3399-linux.dtsi` already includes the VOP clock set; `drm_logo` reserved memory deleted like Toybrick |
| aliases | (none in 6.1 base; NPU commit removed them) | `mmc0 = sdhci` (eMMC), `mmc1 = sdmmc` | stable `mmcblk` numbering |
| console | `fiq_debugger` serial-id 0, 115200, `uart0_xfer` | same | UART0 on header pins 8/10; `uart0` node itself stays disabled |
| PMIC RK809 (I2C0 0x20) | full regulator set | identical voltages (`vdd_center` 0.925-1.025 V, `vcc_buck5` 3.3 V, `vcc_1v8` 1.85 V ...), `rk808-clkout2` clock, codec | Toybrick values differ (2.2 V buck5 etc.), ASUS's were kept |
| `vdd_cpu_b` / `vdd_gpu` | FAN53555 at I2C0/0x60 and I2C8/0x60, vsel GPIO1_C1 / GPIO1_B6 | same | |
| `vdd_log` | PWM regulator config only via suspend flags | `regulator-fixed` 0.9 V, `pwm2` enabled | U-Boot programs the PWM, the kernel leaves it (Toybrick approach); `dmc` disabled |
| eMMC | `sdhci` + `mmc-pwrseq-emmc` reset GPIO2_A4 | same | HS400 ES from `rk3399pro.dtsi` |
| microSD | UHS SDR12-104, 10 mA pad drive overrides | same | |
| SDIO | `sdio0` enabled (leftover), `sdio_pwrseq` on WIFI_REG_ON | `sdio0` disabled; `sdio_pwrseq` kept disabled only because `rk3399pro.dtsi` references it | Wi-Fi is PCIe on this board |
| PCIe | `pcie0`/`pcie_phy` enabled (EP reset GPIO0_B4 from `rk3399pro.dtsi`) | same + `vpcie3v3-supply = vcc_wifi` | `vcc_wifi` is a fixed regulator on **GPIO2_D3 (WL_REG_ON)**, enabled by the PCIe host before link training |
| Bluetooth | `wireless-bluetooth` (rfkill-bt) reset GPIO2_D4 | `vcc_bt` fixed regulator, always on, GPIO2_D4 | USB BT (13d3:3548) needs the line high; rfkill-bt's UART assumptions do not apply |
| Wi-Fi platdata | `wireless-wlan` rtl8822be (wrong chip name) | dropped | upstream rtw88 needs no platdata |
| Ethernet | `gmac` RGMII, reset GPIO3_B7, delays 0/16000/72000, tx 0x23 rx 0x22, `clkin_gmac` 125 MHz input, ASUS `wolirq-gpio`/`wakeup-enable` | same minus the ASUS-only properties | |
| USB2 hosts | EHCI/OHCI 0 and 1 enabled, `u2phy0/1` host ports on `vcc5v0_usb` | same | NPU's USB 2.0 link and Type-A ports go through the GL3523 hub |
| USB3 host (`usbdrd3_1`) | enabled | enabled, `dr_mode = host`, `snps,dis-u3-autosuspend-quirk` | hub + NPU SuperSpeed; quirk from the Toybrick NPU commit |
| **Type-C** | Rockchip 4.4 `fairchild,fusb302` extcon driver (int GPIO1_A2, vbus GPIO4_D1 + GPIO2_D2), `extcon` on dwc3/u2phy/tcphy/cdn_dp | upstream TCPM: `fcs,fusb302` with `interrupts` + `int-n-gpios` (this tree's driver wants the GPIO), `vbus-supply = vbus_typec` (fixed regulator GPIO4_D1), `usb-c-connector` (dual data/power, try-sink, 5 V PDOs), `ports` -> `usbdrd_dwc3_0` role switch, connector `port@0` -> `tcphy0` **orientation switch**; `usbdrd_dwc3_0` `dr_mode = otg` + `usb-role-switch`; `usbdrd3_0 extcon = u2phy0` (charger detection) | pattern taken from `rk3399pro-evb-v11-linux.dts` in the same tree; the 4.4 second VBUS GPIO (GPIO2_D2) is left alone (function unknown) |
| DisplayPort over Type-C | `cdn_dp` enabled with extcon | **disabled** | cdn-dp needs an extcon bridge from TCPM that this tree lacks; Toybrick disables it too |
| HDMI | `hdmi` + phy table, `hdmi_in_vopb`, `route_hdmi` | same, `hdmi_sound` simple card on I2S2 | 4.4 used `rockchip,rk3399-hdmi-dp` sound which no longer exists |
| analogue audio | `rk809-sound` simple card on I2S1, `rk_headset` GPIO0_B5/ADC3 | same | |
| LEDs | pwr GPIO0_A5, act GPIO0_A3 (mmc trigger), rsv GPIO0_B1 | same, labels kept | |
| ADC keys | saradc 2 | same | |
| I2C1 | mpu6500 + ak8963 (Rockchip sensor-dev drivers), ov5647 camera, 24c08 EEPROM | `invensense,mpu6500` + `asahi-kasei,ak8963` (IIO), `atmel,24c08`, **TC358743** (see below) | RPi cameras can be added back with the upstream `ovti,ov5647` / `sony,imx219` bindings (drivers built as modules) |
| I2C2 | imx219 camera, ft5406 touch | TC358743 (disabled unless the `-hdmirx-csi1` DTB is used) | |
| I2C4 | ASUS DSI bridges/MCU/touch (all disabled or ASUS-only drivers) | bus enabled, no devices | |
| I2C6 / I2C7 (header) | disabled | enabled | |
| ISP / MIPI | `mipi_dphy_rx0` -> `rkisp1_0`, `mipi_dphy_tx1rx1` -> `rkisp1_1` (2 lanes) | same graph with the vendor `rkisp1` nodes (`isp0`/`isp1` vendor v2 nodes disabled), camera power/enable GPIOs as fixed regulators (CSI0: GPIO0_B0 + GPIO2_A3; CSI1: GPIO2_B3 + GPIO2_A2) | |
| NPU | nothing explicit (pinmux `npu_ref_clk` GPIO0_A2, `rk808-clkout2`) | same pinmux, `gpio_init` GPIO parking kept | userspace does the rest through GPIO sysfs 35/56 and debugfs clocks |
| suspend | `rockchip_suspend` config | same | |
| DSI / eDP / LVDS accessories | ASUS bridges + panels | not carried (no 6.1 drivers) | HDMI is the display |
| SPI1/SPI5, UART4, PWM0/1/3 | disabled | disabled | header peripherals; enable in the DTS as needed |

## Things that could not be verified without hardware

* Cable orientation handling through `tcphy0` `orientation-switch` (the EVB pattern in
  this tree) - if SuperSpeed only works in one orientation, remove the connector's
  `port@0` and the `tcphy0` `port` to fall back to the Toybrick arrangement.
* `vbus_typec` (GPIO4_D1) as the only VBUS source switch; ASUS's driver also raised
  GPIO2_D2.
* `vcc_wifi`/`vcc_bt` polarity: derived from the 4.4 tree (`wifi_enable_h` = active high
  enable, `BT,reset_gpio` active high).
* `act-led` trigger `mmc0` follows eMMC activity (rootfs on SD: change to `mmc1`).
* IMU interrupt lines (GPIO3_D2 / GPIO3_D7) come from ASUS's `irq-gpio` properties.

## Building the kernel by hand

```sh
cd src/kernel
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
make O=/tmp/kb rockchip_linux_defconfig
scripts/kconfig/merge_config.sh -O /tmp/kb -m /tmp/kb/.config ../../configs/kernel/{tinker-edge-r,usb-gadget-typec,media-hdmi-rx}.config
make O=/tmp/kb olddefconfig
make O=/tmp/kb -j$(nproc) LOCALVERSION=-tinker-edge-r Image dtbs modules
```
