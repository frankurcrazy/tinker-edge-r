# tinker-edge-r

Build system for a **minimal Ubuntu 22.04 (arm64) image for the ASUS Tinker Edge R**
(Rockchip RK3399Pro) with:

* the RK3399Pro **NPU** usable from Linux (firmware load at boot, `npu_transfer_proxy`,
  RKNN C API and RKNN Toolkit Lite for Python 3.10),
* a **Linux 6.1** Rockchip vendor kernel (Toybrick RK3399ProD base, Tinker Edge R
  device tree written for this project),
* **USB Type-C** with the kernel Type-C class (TCPM + FUSB302), dwc3 **dual role**
  and the **complete USB gadget** stack (configfs + every function + legacy gadgets),
* the **Geekworm X1301** HDMI-to-CSI-2 board (Toshiba TC358743) as a V4L2 capture
  source through the RK3399 ISP,
* everything built **inside a Docker container**, sources managed with a **`repo` manifest**.

The work is split across repositories (see [docs/00-overview.md](docs/00-overview.md)):

| repository | content |
|---|---|
| **this one** | `default.xml` manifest, `docker/`, `build.sh` + `scripts/`, `configs/` (kernel fragments, extlinux template), `patches/`, `docs/` |
| [TB-RK3399ProD-Kernel-6.1](https://github.com/frankurcrazy/TB-RK3399ProD-Kernel-6.1) `tinker-edge-r` | kernel (Rockchip 6.1 + PREEMPT_RT + Toybrick port + Tinker Edge R DTS) |
| [tinker-edge-r-debian-u-boot](https://github.com/frankurcrazy/tinker-edge-r-debian-u-boot) `tinker-edge-r` | ASUS U-Boot 2017.09 (+ one build fix) |
| [tinker-edge-r-rootfs](https://github.com/frankurcrazy/tinker-edge-r-rootfs) | Ubuntu rootfs builder, NPU/gadget/HDMI-RX integration |
| [rockchip-linux/rkbin](https://github.com/rockchip-linux/rkbin), [airockchip/RK3399Pro_npu](https://github.com/airockchip/RK3399Pro_npu) | Rockchip blobs and NPU firmware/userspace (pinned) |

## Quick start

```sh
git clone https://github.com/frankurcrazy/tinker-edge-r && cd tinker-edge-r
./build.sh builder      # docker image (Ubuntu 22.04 + cross toolchains + debootstrap)
./build.sh fetch        # repo init/sync -> src/{kernel,u-boot,rkbin,npu,rootfs}
./build.sh all          # uboot -> kernel -> rootfs -> image -> verify  (out/images/*.img.xz)
```

Write the image to a microSD card (or to the eMMC, see [docs/80-flashing.md](docs/80-flashing.md)):

```sh
xz -dc out/images/tinker-edge-r-ubuntu-22.04-*.img.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

Log in as `tinker` / `tinker` (serial console on the 40-pin header UART0, 115200 8N1;
SSH over Ethernet; or over the Type-C gadget network at `192.168.7.2`).

## Documentation

All documentation lives in [`docs/`](docs/README.md) and is also installed on the
device under `/usr/share/doc/tinker-edge-r/`.

* [00-overview](docs/00-overview.md) - architecture, repositories, what runs where
* [10-build](docs/10-build.md) - building, configuration knobs, container details
* [20-boot-flow](docs/20-boot-flow.md) - boot ROM, U-Boot, extlinux, kernel command line
* [30-partition-layout](docs/30-partition-layout.md) - the disk image
* [40-kernel-port](docs/40-kernel-port.md) - the 4.4 to 6.1 device tree port, node by node
* [50-npu](docs/50-npu.md) - how the NPU works and how to use it
* [60-usb-gadget-typec](docs/60-usb-gadget-typec.md) - Type-C, dual role, gadget functions
* [70-hdmi-rx](docs/70-hdmi-rx.md) - Geekworm X1301 capture
* [80-flashing](docs/80-flashing.md) - SD card, eMMC, maskrom recovery
* [90-decisions](docs/90-decisions.md) - decisions and their reasons, known limitations
* [95-board-notes](docs/95-board-notes.md) - facts gathered from the schematic and the stock image

## Status

Everything in this repository was built and verified on the build host (compiles,
packs, images boot-tested only as far as static checks allow).  The image has
**not yet been booted on hardware** by the author of this build system; the first
boot on the board is the next step and [docs/90-decisions.md](docs/90-decisions.md)
lists what to watch for.
