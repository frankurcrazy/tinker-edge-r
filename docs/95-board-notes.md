# Board notes (schematic + stock image observations)

Sources: ASUS Tinker Edge R schematic (`docs/Tinker_Edge_R_Schematics.pdf`, block
diagram pages), ASUS's 4.4 device tree, and read-only inspection of a Tinker Edge R
running the stock ASUS Debian 10 image (kernel 4.4.194, "leslie_yu@asus-docker-env",
Linaro GCC 6.3.1, February 2022).

## Block diagram facts

| block | detail |
|---|---|
| SoC | RK3399Pro; CPU side 2 x LPDDR4 2 GB (4 GB) at 1600 MHz; NPU side LPDDR3 2 GB |
| storage | 16 GB eMMC (`sdhci`), microSD (`sdmmc`, UHS) |
| NPU link | `USB20_NPU` and `USB30_NPU` nets: the NPU is a USB device behind the on-board GL3523 USB 3.0 hub, not on PCIe |
| PCIe | x1 to the M.2 Key-E slot (Wi-Fi module RTL8822CE: PCIe Wi-Fi, USB 2.0 Bluetooth `13d3:3548`) |
| USB | GL3523 4-port USB 3.0 hub: 3 x Type-A 3.0, NPU; Type-C (`TYPEC0` with FUSB302B, `VCC5V0_TYPEC0_EN`); mini-PCIe (USB 2.0 + SIM) for LTE |
| network | RTL8211F gigabit PHY, RGMII, 125 MHz external clock |
| PMIC | RK809-3 on I2C0 (0x20); FAN53555 at 0x60 on I2C0 (VDD_CPU_B) and on I2C8 (VDD_GPU) |
| display | HDMI; MIPI DSI (I2C4); DP over Type-C |
| cameras | two RPi-style 15-pin CSI-2 connectors: CSI0 (MIPI RX0, I2C1), CSI1 (MIPI TX1/RX1, I2C2) |
| audio | RK809 codec, combo jack (headset detect GPIO0_B5, ADC3), SPDIF, I2S0 on the header |
| header | 40-pin: UART0 (pins 8/10), UART4, I2C6 (3/5), I2C7 (27/28), SPI1, SPI5, I2S0, PWM0/1/3A, SPDIF, CLKOUT |
| misc | EEPROM 24C08 on I2C1 (0x50), MPU6500 IMU (0x68) + AK8963 compass (0x0d) on I2C1, 3 LEDs, ADC buttons, fan header (GPIO fan on Toybrick, not described by ASUS for this board) |

## Stock ASUS Debian 10 image

```
Linux version 4.4.194 (leslie_yu@asus-docker-env) (gcc version 6.3.1 20170404 (Linaro GCC 6.3-2017.05)) #4 SMP Tue Feb 15 03:07:56 UTC 2022
/proc/device-tree/model: ASUS Tinker Edge R
cmdline: storagemedia=emmc androidboot.storagemedia=emmc androidboot.mode=normal ... root=/dev/mmcblk1p8 rw rootwait
         console=tty0 earlycon=uart8250,mmio32,0xff1a0000 swiotlb=1 console=ttyFIQ0 rootfstype=ext4 coherent_pool=1m
```

eMMC layout (`/dev/disk/by-partlabel`, sizes in KiB from `/proc/partitions`):

| p | label | size | note |
|---|---|---|---|
| 1 | uboot | 4096 | |
| 2 | trust | 4096 | |
| 3 | misc | 4096 | |
| 4 | boot | 32768 | Android boot image (kernel + resource.img) |
| 5 | recovery | 98304 | |
| 6 | backup | 32768 | |
| 7 | userdata | 65536 | ext2 (4.9 MB fs), mounted on `/boot`: `config.txt`, `cmdline.txt`, `overlays/*.dtbo`, `display/` - U-Boot reads it with `ext2load mmc 0:7` |
| 8 | rootfs | rest | |

`config.txt` (ASUS): `intf:fiq_debugger=on`, commented `intf:uart0/uart4/i2c6/i2c7/i2s0/spdif/spi1/spi5/pwm0/pwm1/pwm3a=off`,
`conf:eth_wakeup=on`, `conf:auto_ums=on`, CPU/GPU governor and frequency limits applied by
`/etc/init.d/rockchip.sh`, `overlay=` list of DTBOs (CSI0-IMX219, CSI1-OV5647, DP_VOPB, HDMI_VOPL, mipi2lvds/mipi2edp panels, hifiberry-dacplus, panel-asus-DSI1 ...).

NPU on the stock image:

```
/etc/init.d/rockchip.sh: update_npu_fw() { /usr/bin/npu-image.sh; sleep 1; /usr/bin/npu_transfer_proxy& }
/usr/bin/npu-image.sh:  no /sys/devices/platform/f8000000.pcie/pcie_reset_ep -> "upgrading npu with usb image":
                        cd /usr/share/npu_fw && npu_upgrade MiniLoaderAll.bin uboot.img trust.img boot.img
/usr/share/npu_fw:      MiniLoaderAll.bin 160078, uboot.img 2097152, trust.img 2097152, boot.img 20307968, npu_commit_id.xml
/usr/bin:               npu_powerctrl, npu_powerctrl_combine, npu_transfer_proxy, npu_upgrade, npu_upgrade_pcie(_combine), upgrade_tool, npu-image.sh
npu_powerctrl strings:  /sys/class/gpio/{export,unexport}, %s/gpio%s/direction|value, gpio "35" and "56",
                        /sys/kernel/debug/clk/clk_wifi_pmu/clk_enable_count, /sys/kernel/debug/clk/rk808-clkout2/clk_enable_count,
                        /sys/bus/platform/devices/fe380000.usb, fe3a0000.usb (EHCI/OHCI host 0)
lsusb:                  2207:0019 Fuzhou Rockchip (NPU) twice: on the USB 3.0 bus behind hub 05e3:0620 and on the 2.0 bus behind hub 05e3:0610;
                        13d3:3548 IMC Networks (Bluetooth of the RTL8822CE)
npu_transfer_proxy devices:  9085cc156ba59799    c79f56a7    USB_DEVICE
/proc/device-tree:      usb0/dwc3@fe800000 dr_mode=otg (Type-C), usb1/dwc3@fe900000 dr_mode=host; /sys/class/udc/fe800000.dwc3 maximum_speed=super-speed
dpkg:                   none of the npu files belong to a package (installed by the rootfs build)
```

Power-management hooks: `/etc/Powermanager/01npu` -> `/usr/lib/pm-utils/sleep.d/`,
`02npu` -> `/lib/systemd/system-sleep/` (NPU reload after suspend), `rk_wifi_init /dev/ttyS0`,
`ssh-keygen -A` and `npu_transfer_proxy&` in `/etc/rc.local`.

## ASUS public repositories used

* `TinkerBoard2/debian` (branch `linux4.19-rk3399-debian10`, Apache-2.0): `overlay-firmware/usr/bin/{upgrade_tool,npu_powerctrl,npu_upgrade,npu-image.sh,...}`, `overlay-firmware/usr/share/npu_fw*`, `overlay/etc/init.d/rockchip.sh`, `mk-rootfs-*.sh`.
* `frankurcrazy/tinker-edge-r-debian-kernel` (4.4) and `frankurcrazy/tinker-edge-r-debian-u-boot` (2017.09): forks of ASUS's sources.

## Rockchip references

* `airockchip/RK3399Pro_npu`: NPU firmware sets (USB and PCIe), `npu_transfer_proxy`, RKNN API 1.7.5 and its user guide.
* `rockchip-linux/rknn-toolkit`: model conversion (x86) and `rknn-toolkit-lite` wheels (cp35-cp310 aarch64).
* `rockchip-linux/rkbin`: `RKBOOT/RK3399PROMINIALL.ini` (DDR 800 MHz v1.30, usbplug/miniloader v1.26), `RKTRUST/RK3399PROTRUST.ini` (BL31 v1.35, BL32 v2.12).
