# Flashing and recovery

## microSD card (recommended for the first boot)

```sh
xz -dc out/images/tinker-edge-r-ubuntu-22.04-<date>.img.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
# or, with bmap-tools:  sudo bmaptool copy out/images/<name>.img.xz /dev/sdX
```

Insert the card and power the board.  Note the boot ROM order: **eMMC first**.  While
the eMMC still holds ASUS's image, the eMMC's U-Boot runs, fails its Android boot, and
its distro boot scans the microSD (`mmc 1`) *before* the eMMC - so it boots this image's
kernel and rootfs from the card with ASUS's bootloader.  That works, but to run the
image's own U-Boot/trust from the card the eMMC must be erased or hold no valid loader
(see maskrom below).

## eMMC

### From the running Ubuntu (on microSD)

```sh
xz -dc /path/to/image.img.xz | sudo dd of=/dev/mmcblk0 bs=4M status=progress conv=fsync
sudo sync; sudo poweroff
```
(`mmcblk0` is the eMMC with this kernel; double-check with `lsblk -o NAME,SIZE,PARTLABEL`.)
Remove the card and power on.

### Through maskrom / rkdeveloptool (from a PC over the Type-C port)

1. Install `rkdeveloptool` (`apt install rkdeveloptool` on Ubuntu 22.04+, or build from
   `https://github.com/rockchip-linux/rkdeveloptool`).
2. Enter maskrom mode: hold the **recovery button** while powering on (the ASUS manual:
   "Recovery" button next to the power button; the schematic also shows a "MASKROM"
   jumper), or, from a running Linux, `sudo reboot loader` (Rockchip U-Boot honours it) /
   `echo loader > /sys/...` is not needed: `sudo rkdeveloptool rd 3` when already in loader mode.
3. Connect the Type-C port to the PC; `rkdeveloptool ld` lists the device (Maskrom).
4. ```sh
   rkdeveloptool db  out/u-boot/rk3399pro_loader_v1.30.126.bin   # load the loader into RAM
   rkdeveloptool wl  0 out/images/tinker-edge-r-ubuntu-22.04-<date>.img   # write the whole image at LBA 0
   rkdeveloptool rd                                              # reboot
   ```
   (`wl` takes an uncompressed image; `xz -d` first.)

### U-Boot UMS (USB mass storage)

ASUS's U-Boot can export the eMMC as a USB disk over the Type-C port: interrupt the
U-Boot prompt on UART2 and run `ums 0 mmc 0`; the eMMC appears on the PC as a block
device and can be written with `dd`.  (ASUS's `config.txt` `auto_ums` feature only
works with their Android-style boot partition.)

## Erasing the eMMC to boot from microSD with the card's own bootloader

From Linux on the board: `sudo dd if=/dev/zero of=/dev/mmcblk0 bs=1M count=16` wipes the
loader area (sectors 64-32768) so the boot ROM moves on to the microSD.  Or use
`rkdeveloptool ef` in maskrom mode.

## Going back to ASUS's image

Download the official Tinker Edge R Debian image from ASUS and write it with
`rkdeveloptool wl 0 <image>` in maskrom mode (or `dd` it to the eMMC from the SD-card
system).  Nothing in this image touches ASUS's partition layout permanently.

## Serial console for troubleshooting

UART0 on the 40-pin header (pin 8 TX, pin 10 RX, pin 6 GND), 115200 8N1, shows the
kernel from `earlycon` onwards and gives a login prompt.  U-Boot's own messages are on
UART2 (not on the header) - the extlinux menu timeout (3 s) still applies; the default
entry boots automatically.
