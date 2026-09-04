# ASUS U-Boot: config.txt / cmdline.txt / overlays

`common/image-android.c` in `tinker-edge-r-debian-u-boot` (branch `linux4.4-rk3399pro`):

* `parse_hw_config()` loads `config.txt` with `ext2load mmc <devnum>:7` (partition **7**
  hard-coded, `conf_addr = 0x01200000`) and parses lines:
  * `intf:<name>=on|off` for `fiq_debugger uart0 uart4 i2c6 i2c7 i2s0 spdif spi1 spi5 pwm0 pwm1 pwm3a` (uart4/spi1 and fiq_debugger/uart0 are mutually exclusive) -> DT nodes toggled in the kernel FDT before boot;
  * `conf:eth_wakeup=on|off`, `conf:auto_ums=on|off`;
  * `overlay=<name> <name>...` -> `overlays/<name>.dtbo` applied with libfdt overlay support (`CONFIG_OF_LIBFDT_OVERLAY`, `CONFIG_CMD_DTIMG`).
* `cmdline.txt` (`cmdline_addr = 0x01800000`) appends to the kernel command line.
* All of it runs only inside the **Android boot image path** (`boot_android`), i.e. when
  the `boot` partition holds an Android boot image with `resource.img`.  With an ext4
  boot partition and extlinux none of this code runs; the kernel DTB is taken from the
  `fdt` line of `extlinux.conf` unmodified.
* UMS: `arch/arm/mach-rockchip/boot_mode.c` sets `preboot = ums 0 mmc 0` for the
  "ums" boot mode (reboot loader/BCB); `conf:auto_ums` toggles the same when USB is
  connected at power-on.

Consequences for this image: interface enable/disable = edit the DTS (or add a DTB
variant), no DTBO overlays (this U-Boot's `sysboot` predates `fdtoverlays`).
