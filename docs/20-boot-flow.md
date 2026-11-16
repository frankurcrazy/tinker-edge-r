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
partitions, and `run distro_bootcmd` takes over.

The boot ROM prefers the eMMC, so on a board that still has ASUS's system on the eMMC
it is the eMMC's loader and U-Boot that run, and they decide which medium to boot:

* `RKIMG_DET_BOOTDEV` (`rockchip-common.h`) runs `rkimgtest mmc 1`, which succeeds when
  the microSD has a Rockchip loader header (magic `0xFCDC8C3B`) at **sector 64**, as
  this image does.  `devtype/devnum` then point at the card, `boot_android` and
  `bootrkp` fail on it, and distro boot runs this card's extlinux entry.
* Without that header (a card written without the loader area, or with sector 64
  cleared) `devnum` stays at the eMMC and `bootrkp` boots ASUS's system from it,
  card or no card.  Clearing and restoring the card's sector 64 from a running system
  therefore switches between the two without touching the card (verified on the
  board, 2026-11-16).

To boot fully from the SD card's own U-Boot the eMMC must not contain a valid loader
(see [80-flashing.md](80-flashing.md)).

### U-Boot environment

`CONFIG_ENV_IS_IN_MMC`, `CONFIG_ENV_OFFSET=0x3f8000`, `CONFIG_ENV_SIZE=0x8000`: the
environment lives at 4 MiB - 32 KiB of the boot device, inside the gap between
`idbloader` and the first partition, so it never collides with partitions.  `saveenv`
works (ASUS enabled it).

### Serial consoles

| console | UART | pins | baud |
|---|---|---|---|
| U-Boot / miniloader | UART2 (`0xff1a0000`, `CONFIG_DEBUG_UART_BASE`) | not wired to any connector on this board, so U-Boot's output and its extlinux menu cannot be reached | 115200 |
| kernel early console | UART2 (`earlycon=uart8250,mmio32,0xff1a0000`) | same UART as U-Boot: nothing to see, but harmless | 115200 |
| kernel | UART0 through the Rockchip fiq debugger (`ttyFIQ0`) | 40-pin header pins 8 (TX) / 10 (RX), same as ASUS's Debian image | 115200 8N1 |
| HDMI | `tty0` | framebuffer console | |
| USB gadget | `ttyGS0` (ACM function) | Type-C port when a host is attached | any |

`earlycon` must stay on UART2.  U-Boot sets that UART up; nothing before the kernel
touches UART0, and the 8250 early console given no baud rate assumes the UART is
already configured, so on UART0 its first character waits forever for a transmitter
that never empties: the kernel hangs before printing anything.  That was why the first
images did not boot.  UART0 shows the whole kernel log anyway once `ttyFIQ0` registers
(the log buffer is replayed).

### Kernel command line

Set by `extlinux.conf` (`configs/extlinux.conf.in`, `KERNEL_CMDLINE` in `board.env`):

```
root=PARTUUID=<rootfs>  earlycon=uart8250,mmio32,0xff1a0000 console=ttyFIQ0,115200n8 console=tty0
rw rootwait rootfstype=ext4 swiotlb=1 coherent_pool=1m cgroup_enable=memory clk_ignore_unused
```

`swiotlb=1 coherent_pool=1m` are the Rockchip defaults from `rk3399-linux.dtsi`.
`clk_ignore_unused` keeps clocks that no driver claims running: every boot on the
board so far had it, and testing without it needs someone at the board in case it
hangs (see [90-decisions.md](90-decisions.md)).

The device tree must not carry `/chosen/bootargs`.  Rockchip's U-Boot merges it
**over** the `append` line (`fdt_chosen()` calls `env_update_filter()`,
`cmd/nvedit.c`): every DTB argument replaces the environment argument with the same
key, so the DTB wins.  `rk3399-linux.dtsi` sets `earlycon` there, and once the Tinker
DTS pointed it at UART0, no `append` line could fix the hang.  The Tinker DTS deletes
the property, so the command line is the `append` line alone.

### extlinux menu

```
default tinker-edge-r          no HDMI-RX board (default DTB)
label hdmirx-csi0              X1301 HDMI-RX board on CSI0 (rk3399pro-tinker-edge-r-hdmirx-csi0.dtb)
label hdmirx-csi1              X1301 HDMI-RX board on CSI1 (rk3399pro-tinker-edge-r-hdmirx-csi1.dtb)
label rescue                   systemd rescue target
```

The U-Boot console is not reachable, so the menu cannot be used: edit `default` (or
the command lines) in `/boot/extlinux/extlinux.conf` on the device.

### First boot

`tinker-first-boot.service` grows the root partition to the size of the medium
(`growpart` + `resize2fs`), regenerates SSH host keys and `/etc/machine-id`, and
writes its stamp.  The kernel mounts the root as `/dev/root` without an initramfs, so
the script finds the partition through the root mount's major:minor; it keeps
`growpart`'s temporary files on `/run` (the image's root filesystem has little free
space until it is grown) and tries again at the next boot if growing failed.
`tinker-eth-mac.service` gives `eth0` the board's MAC address from the EEPROM before
networkd starts (see [95-board-notes.md](95-board-notes.md)).
`npu-firmware.service` then loads the NPU (about 10-20 s).
