# The NPU

## Hardware

The RK3399Pro package contains the RK3399 application processor and a separate NPU
die (an RK1808-class core, 3 TOPS) with its own 2 GB LPDDR3.  The NPU is a computer of
its own: it boots a Rockchip firmware (miniloader, U-Boot, trust, and a Linux `boot.img`
that runs `rknn_server`) and talks to the host over **USB** on the Tinker Edge R
(schematic nets `USB20_NPU` and `USB30_NPU`; Rockchip's reference boards use PCIe
instead).  It has no storage, so the host has to push the firmware into its RAM on
every power-up:

```
npu-firmware.service
  └─ /usr/local/sbin/npu-firmware-load
       └─ /usr/bin/npu_upgrade MiniLoaderAll.bin uboot.img trust.img boot.img
            ├─ npu_powerctrl -i / -o   reset the NPU into maskrom mode:
            │                          GPIO 35 (GPIO1_A3) and 56 (GPIO1_D0) via /sys/class/gpio,
            │                          NPU reference clocks via /sys/kernel/debug/clk/{clk_wifi_pmu,rk808-clkout2}/clk_enable_count
            ├─ upgrade_tool ld / db MiniLoaderAll.bin / td      maskrom protocol over USB 2.0
            ├─ upgrade_tool wl 0x20000 uboot.img, wl 0x20800 trust.img, wl 0x21000 boot.img
            └─ upgrade_tool rs ...                               run
  (about 10-20 s; then the NPU's Linux appears as a Rockchip USB device 2207:0019 on the USB 3.0 hub)
npu-transfer-proxy.service
  └─ /usr/bin/npu_transfer_proxy        transport between librknn_api and rknn_server (USB_DEVICE mode)
```

This is exactly what the stock ASUS Debian 10 image does (`/etc/init.d/rockchip.sh` ->
`/usr/bin/npu-image.sh` -> `npu_upgrade`), with the same binaries.  The 6.1 kernel tree
was adapted by its maintainer for this userspace (writable `clk_enable_count` in
debugfs, GPIO sysfs enabled).

Files and their origins: `src/rootfs/npu/PROVENANCE.md`.

| path on the device | content |
|---|---|
| `/usr/share/npu_fw/` | `MiniLoaderAll.bin`, `uboot.img`, `trust.img`, `boot.img` (USB-mode set, RKNN 1.7.5) |
| `/usr/bin/npu_upgrade`, `/usr/bin/npu_powerctrl`, `/usr/bin/upgrade_tool` | firmware push tools |
| `/usr/bin/npu_transfer_proxy` | transport daemon |
| `/usr/lib/aarch64-linux-gnu/librknn_api.so`, `/usr/include/rknn_api.h` | RKNN C API |
| `/usr/share/rknn-api/examples`, `/usr/share/rknn-api/doc` | C demos (mobilenet, ssd, yolov5, ...) and the RKNN API user guide (PDF) |
| Python: `rknn.api` / `rknnlite.api` (`rknn_toolkit_lite` 1.7.5, cp310) | on-device inference from Python 3.10 |
| `/usr/local/bin/npu-status` | health check |

## Checking that it works

```sh
npu-status                         # services, USB devices, proxy
systemctl status npu-firmware      # "NPU firmware loaded in 12s"
lsusb | grep 2207:                 # Bus ... ID 2207:0019 Fuzhou Rockchip Electronics Company
npu_transfer_proxy devices         # List of ntb devices attached
                                   # <serial>    <id>    USB_DEVICE
cat /tmp/npu.log                   # step-by-step log of the last firmware push
```

Run a C demo (models are included):

```sh
cd /usr/share/rknn-api/examples/rknn_mobilenet_demo && cat README* 2>/dev/null
gcc -O2 -o /tmp/mobilenet src/main.cc -I/usr/include -I3rdparty/... -lrknn_api -lstdc++ ...   # see the demo's build script
```

Python (RKNN Toolkit Lite):

```python
from rknnlite.api import RKNNLite
r = RKNNLite()
r.load_rknn('/usr/share/rknn-api/examples/rknn_mobilenet_demo/model/mobilenet_v1_rk3399pro.rknn')
r.init_runtime()
out = r.inference(inputs=[img])   # img: numpy HWC uint8 224x224x3
```

Models are converted on an x86 host with `rknn-toolkit` 1.7.5
(`https://github.com/rockchip-linux/rknn-toolkit`, target `rk3399pro`); the same
version must be used on both sides.

## Kernel-side requirements (all satisfied by the port)

* `usbdrd3_1` host + EHCI/OHCI hosts: the NPU's maskrom USB 2.0 port and its USB 3.0
  runtime port sit behind the on-board GL3523 hub.
* `npu_ref_clk` pinmux (GPIO0_A2 function 1) and the RK809 `rk808-clkout2` clock: the
  NPU's reference clocks, switched by `npu_powerctrl` through debugfs.
* GPIO1_A3 and GPIO1_D0 free for sysfs export (`CONFIG_GPIO_SYSFS=y`), debugfs
  mounted (systemd does it), `CONFIG_DEBUG_FS=y`.
* No NPU driver is needed on the AP side.

## Troubleshooting

* `failed to wait device` in `/tmp/npu.log`: the NPU did not enter maskrom mode -
  check `ls /sys/class/gpio` for `gpio35`/`gpio56` after `npu_powerctrl -i`, and that
  `/sys/kernel/debug/clk/clk_wifi_pmu/clk_enable_count` exists and is writable.
* `upgrade_tool` errors: it needs root and raw USB access (`/dev/bus/usb`); run
  `systemctl restart npu-firmware`.
* Proxy says `PCIE` instead of `USB_DEVICE`: wrong firmware set (the PCIe set is in
  `src/npu/drivers/npu_firmware/npu_pcie_fw`, not installed).
* After suspend/resume the NPU must be reloaded: `systemctl restart npu-firmware npu-transfer-proxy`
  (ASUS shipped pm-utils hooks for this; a systemd sleep hook is a possible addition).
* NPU firmware and host library versions must match; both come from
  `airockchip/RK3399Pro_npu` at the pinned commit.
