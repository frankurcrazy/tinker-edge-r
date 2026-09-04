# Boot flow

## Chain

| stage | where | what |
|---|---|---|
| boot ROM (RK3399Pro, same as RK3399) | SoC | reads `idbloader.img` from **sector 64** of the eMMC (first) or microSD; falls back to USB maskrom mode when nothing valid is found or the recovery button is held |
| `idbloader.img` | `rkbin/bin/rk33/rk3399pro_ddr_800MHz_v1.30.bin` + `rk3399pro_miniloader_v1.26.bin` wrapped by `mkimage -T rksd` | DDR init, then the miniloader loads `trust.img` and `uboot.img` from their fixed sectors |
| `trust.img` | sector 24576, `rkbin` `RKTRUST/RK3399PROTRUST.ini` (BL31 `rk3399pro_bl31_v1.35.elf` + BL32 `rk3399pro_bl32_v2.12.bin`) | ARM Trusted Firmware + OP-TEE |
| `uboot.img` | sector 16384, U-Boot proper packed by `loaderimage` (4 copies of 1 MiB, load address `0x00200000`) | ASUS U-Boot 2017.09 (`tinker_edge_r_defconfig`) |
| U-Boot `bootcmd` | `RKIMG_BOOTCOMMAND` from `include/configs/rockchip-common.h` | `boot_android ${devtype} ${devnum}; bootrkp; run distro_bootcmd;` |
| distro boot | `include/config_distro_bootcmd.h` | for `mmc 1` (microSD) then `mmc 0` (eMMC), then USB: scan partitions with the **bootable** flag for `/extlinux/extlinux.conf`, load `kernel`/`fdt`, set `bootargs` from `append`, `booti` |
| kernel | `Image` + `rk3399pro-tinker-edge-r.dtb` from the boot partition | Linux 6.1.118-rt45-tinker-edge-r |
| userspace | `root=PARTUUID=...` | systemd |

### How U-Boot ends up in distro boot

`boot_android` looks for an Android boot image in the partition named `boot` and, for
the ASUS image, also reads `config.txt`/`cmdline.txt` from **partition 7** with
`ext2load mmc 0:7` (`common/image-android.c`).  Our `boot` partition holds an ext4
filesystem, so the Android header check fails, `bootrkp` finds no `kernel`/`resource`
partitions, and `run distro_bootcmd` takes over.  Because the microSD (`mmc 1`) is
scanned first, an SD card with this image boots even when the eMMC still has the ASUS
system, provided the eMMC's U-Boot is used (the boot ROM prefers eMMC): the ASUS
U-Boot on the eMMC will run our SD card's extlinux entry.  To boot fully from the SD
card's own U-Boot the eMMC must not contain a valid loader (see [80-flashing.md](80-flashing.md)).

`RKIMG_DET_BOOTDEV` in `rockchip-common.h` sets `devtype/devnum` for the Android path
(`rkimgtest mmc 1` succeeds only for Rockchip-style SD images), which does not affect
the distro scan order.

### U-Boot environment

`CONFIG_ENV_IS_IN_MMC`, `CONFIG_ENV_OFFSET=0x3f8000`, `CONFIG_ENV_SIZE=0x8000`: the
environment lives at 4 MiB - 32 KiB of the boot device, inside the gap between
`idbloader` and the first partition, so it never collides with partitions.  `saveenv`
works (ASUS enabled it).

### Serial consoles

| console | UART | pins | baud |
|---|---|---|---|
| U-Boot / miniloader | UART2 (`0xff1a0000`, `CONFIG_DEBUG_UART_BASE`) | UART2 is muxed on SDMMC data pins on the RK3399Pro; ASUS's config keeps U-Boot on it (not exposed on the 40-pin header) | 115200 |
| kernel | UART0 through the Rockchip fiq debugger (`ttyFIQ0`) | 40-pin header pins 8 (TX) / 10 (RX), same as ASUS's Debian image | 115200 8N1 |
| HDMI | `tty0` | framebuffer console | |
| USB gadget | `ttyGS0` (ACM function) | Type-C port when a host is attached | any |

`earlycon=uart8250,mmio32,0xff180000` prints the first kernel messages on UART0.

### Kernel command line

Set by `extlinux.conf` (`configs/extlinux.conf.in`, `KERNEL_CMDLINE` in `board.env`):

```
root=PARTUUID=<rootfs>  earlycon=uart8250,mmio32,0xff180000 console=ttyFIQ0,115200n8 console=tty0
rw rootwait rootfstype=ext4 swiotlb=1 coherent_pool=1m cgroup_enable=memory
```

`swiotlb=1 coherent_pool=1m` are the Rockchip defaults from `rk3399-linux.dtsi`.
The `chosen/bootargs` in the DTB is overridden by U-Boot with the `append` line
(Rockchip's U-Boot merges DTB and environment bootargs).

### extlinux menu

```
default tinker-edge-r          HDMI-RX board on CSI0 (default DTB)
label hdmirx-csi1              HDMI-RX board on CSI1 (rk3399pro-tinker-edge-r-hdmirx-csi1.dtb)
label rescue                   systemd rescue target
```

`timeout 30` (3 s) on the U-Boot console lets you pick an entry with the serial
console attached; edit `/boot/extlinux/extlinux.conf` on the device to change the
default or the command line.

### First boot

`tinker-first-boot.service` grows the root partition to the size of the medium
(`growpart` + `resize2fs`), regenerates SSH host keys and `/etc/machine-id`, and
disables itself.  `npu-firmware.service` then loads the NPU (about 10-20 s).
