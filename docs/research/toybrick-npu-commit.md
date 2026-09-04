# The 6.1 tree's NPU commit (3b7aa56246 "Update Toybrick RK3399ProD with NPU support")

3382 insertions, 58 deletions.  What matters for the Tinker Edge R:

| file | change | relevance |
|---|---|---|
| `arch/arm64/boot/dts/rockchip/rk3399pro-toybrick*.dts[i]` (new) | Toybrick board files: NPU over USB (`pcie0` disabled), `usbhub_reset` node (GPIO4_C5), `usb3_host_en` pinmux (GPIO2_A2), FUSB302 node with `int-n-gpios`/`vbus-5v-gpios`, dwc3_0 `usb-role-switch` | template for the 6.1 bindings; GPIOs differ on the Tinker |
| `rk3399pro.dtsi` | eMMC/SD/SDIO defaults moved here (`sdhci` HS400 ES, `sdmmc` UHS, `sdio0` with `mmc-pwrseq = <&sdio_pwrseq>`) | the Tinker DTS must define `sdio_pwrseq` even if unused |
| `rk3399-linux.dtsi` | mmc aliases removed, bootargs reduced to `earlycon ... swiotlb=1 coherent_pool=1m` | our DTS re-adds aliases |
| `rk3399.dtsi` | node renames (`gpioN@`, `dwmmc@`, `sdhci@`), `snps,xhci-slow-suspend-quirk` | cosmetic / xhci quirk |
| `drivers/clk/clk.c` | `clk_enable_count` in debugfs made **writable** ("keep the old ABI for Toybrick userland") | `npu_powerctrl` writes it |
| `drivers/mfd/rk808.c` | only instantiate MFD cells present in DT | RK809 without battery/charger nodes |
| `drivers/usb/dwc3/host.c`, `drivers/usb/host/xhci-plat.c` | `snps,dis-u3-autosuspend-quirk` -> disable USB3 autosuspend on the root hub | keeps the NPU link alive |
| `drivers/usb/misc/usbhub_reset.c` (new, `CONFIG_USB_USBHUB_RESET`) | hold a hub reset GPIO high, drop it on reboot/shutdown | Toybrick hub; not needed on the Tinker (no such GPIO in ASUS's DTS) |
| `drivers/usb/typec/tcpm/fusb302.c` | accept `int-n` and `vbus-5v` GPIO names, VBUS regulator optional | lets the Rockchip-style properties work with upstream TCPM |
| `drivers/phy/rockchip/phy-rockchip-inno-usb2.c` | optional IRQ, quieter | |
| `drivers/net/wireless/realtek/rtw88/usb.c` etc. (new) | RTL8723DU USB Wi-Fi for the Toybrick | not used on the Tinker (RTL8822CE PCIe) |
| `arch/arm64/configs/rockchip_linux_defconfig` | `CONFIG_EXTRA_FIRMWARE` with rtl8723d blobs (**.bin files not in git -> build breaks from a clean clone**), rtw88, gpio-fan, fbcon, `USB_USBHUB_RESET`, `AUTOFS_FS` | our fragment clears `EXTRA_FIRMWARE` |
| `make_toybrick_boot_linux.sh` (new) | builds a 64 MiB ext2 `boot_linux.img` with `extlinux/extlinux.conf` (`kernel /extlinux/Image`, `fdt`, `initrd`, `root=PARTUUID=614e0000-...`) for the legacy Toybrick U-Boot | proves extlinux boot on this U-Boot generation |
