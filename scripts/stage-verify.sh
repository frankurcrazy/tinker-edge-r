#!/usr/bin/env bash
# Stage: static verification of the newest image in out/images (no mounting,
# no root): GPT layout, boot partition content, device-tree properties that the
# NPU / Type-C / HDMI-RX features rely on, and rootfs contents via debugfs.
# Exit code 1 if any check fails.
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

IMG="${1:-$(ls -t "$OUT"/images/*.img 2>/dev/null | head -1)}"
[ -f "$IMG" ] || die "no image found in $OUT/images (build one first, or pass a path)"
for t in sgdisk debugfs dtc; do command -v "$t" >/dev/null || die "missing tool: $t"; done
W="$(mktemp -d "${TMPDIR:-/tmp}/verify.XXXXXX")"; trap 'rm -rf "$W"' EXIT
fail=0
ok()   { printf '  \033[1;32mok\033[0m   %s\n' "$*"; }
bad()  { printf '  \033[1;31mFAIL\033[0m %s\n' "$*"; fail=1; }
check(){ if eval "$1"; then ok "$2"; else bad "$2"; fi; }

stage_banner "verify $(basename "$IMG")"

# ---- GPT ------------------------------------------------------------------------------
sgdisk -p "$IMG" > "$W/gpt.txt" 2>&1 || bad "sgdisk -p failed"
part_start() { awk -v n="$1" '$1==n {print $2}' "$W/gpt.txt"; }
part_end()   { awk -v n="$1" '$1==n {print $3}' "$W/gpt.txt"; }
check '[ "$(part_start 1)" = 16384 ]'  "uboot partition starts at LBA 16384"
check '[ "$(part_start 2)" = 24576 ]'  "trust partition starts at LBA 24576"
check '[ "$(part_start 4)" = "'"$IMG_SECTOR_BOOT"'" ]' "boot partition starts at LBA $IMG_SECTOR_BOOT"
check 'grep -qE "^ +4 .* boot$" "$W/gpt.txt"'   "partition 4 named boot"
check 'grep -qE "^ +5 .* rootfs$" "$W/gpt.txt"' "partition 5 named rootfs"
check 'sgdisk -A 4:show "$IMG" | grep -q "legacy BIOS bootable"' "boot partition has the legacy-bootable attribute (U-Boot distro scan)"
ROOT_PARTUUID="$(sgdisk -i 5 "$IMG" | sed -n 's/^Partition unique GUID: //p' | tr 'A-F' 'a-f')"
BOOT_PARTUUID="$(sgdisk -i 4 "$IMG" | sed -n 's/^Partition unique GUID: //p' | tr 'A-F' 'a-f')"

# ---- raw blobs -----------------------------------------------------------------------
dd if="$IMG" of="$W/idb.bin" bs=512 skip=64 count=8 status=none
# mkimage -T rksd RC4-scrambles the 512-byte header; the 0x0ff0aa55 signature shows up as 3b8cdcfc be9f9d51.
check 'head -c 8 "$W/idb.bin" | xxd -p | grep -qi "^3b8cdcfcbe9f9d51"' "idbloader present at LBA 64 (scrambled RK boot-ROM signature)"
dd if="$IMG" of="$W/uboot.bin" bs=512 skip=16384 count=8 status=none
check 'grep -q "LOADER" "$W/uboot.bin" || strings "$W/uboot.bin" | grep -q "LOADER"' "uboot.img present at LBA 16384 (loaderimage header)"
dd if="$IMG" of="$W/trust.bin" bs=512 skip=24576 count=8 status=none
check 'grep -aq "BL3" "$W/trust.bin" || strings "$W/trust.bin" | grep -q "BL3"' "trust.img present at LBA 24576"

# ---- boot partition ------------------------------------------------------------------
dd if="$IMG" of="$W/boot.img" bs=512 skip="$(part_start 4)" count=$(( $(part_end 4) - $(part_start 4) + 1 )) status=none
dbg() { debugfs -R "$1" "$2" 2>/dev/null; }
dbg "cat /extlinux/extlinux.conf" "$W/boot.img" > "$W/extlinux.conf"
check '[ -s "$W/extlinux.conf" ]' "extlinux/extlinux.conf readable"
check 'grep -q "root=PARTUUID=$ROOT_PARTUUID" "$W/extlinux.conf"' "extlinux root=PARTUUID matches the rootfs partition GUID"
check 'grep -q "fdt /dtbs/$KERNEL_DEFAULT_DTB" "$W/extlinux.conf"' "default entry uses $KERNEL_DEFAULT_DTB"
dbg "ls -l /" "$W/boot.img" > "$W/bootls.txt"
check 'grep -q " Image$" "$W/bootls.txt"' "Image on the boot partition"
dbg "dump /Image $W/Image" "$W/boot.img" >/dev/null
check '[ "$(stat -c %s "$W/Image")" -gt 20000000 ]' "Image is a plausible arm64 kernel ($(stat -c %s "$W/Image" 2>/dev/null) bytes)"
check 'xxd -s 56 -l 4 -p "$W/Image" | grep -q "41524d64"' "Image has the ARM64 magic"
check 'tune2fs -l "$W/boot.img" 2>/dev/null | grep -q "^Filesystem features:.*extent" && ! tune2fs -l "$W/boot.img" | grep -q metadata_csum' "boot ext4 without metadata_csum (2017.09 U-Boot readable)"

# ---- device tree ---------------------------------------------------------------------
dbg "dump /dtbs/$KERNEL_DEFAULT_DTB $W/board.dtb" "$W/boot.img" >/dev/null
dtc -q -I dtb -O dts -o "$W/board.dts" "$W/board.dtb" 2>/dev/null || bad "default DTB does not decompile"
dtprop() { grep -q -- "$1" "$W/board.dts"; }
check 'dtprop "ASUS Tinker Edge R"'            "model = ASUS Tinker Edge R"
check 'dtprop "fcs,fusb302"'                   "FUSB302 TCPM node"
check 'dtprop "usb-c-connector"'               "usb-c-connector present"
check 'dtprop "usb-role-switch;"'              "dwc3 usb-role-switch (dual role)"
check 'dtprop "orientation-switch;"'           "tcphy0 orientation-switch"
check 'dtprop "dr_mode = \"otg\""'             "usbdrd_dwc3_0 dr_mode otg"
check 'dtprop "toshiba,tc358743"'              "TC358743 HDMI-RX node"
check 'dtprop "vpcie3v3-supply"'               "PCIe Wi-Fi power via vpcie3v3-supply"
check 'dtprop "rk808-clkout2"'                 "RK809 clkout2 (NPU reference clock)"
check 'dtprop "rockchip,rk809"'                "RK809 PMIC"
check 'dtprop "mmc0 = \"/mmc@fe330000\"\|mmc0 = \"/sdhci@fe330000\""' "eMMC is mmc0"

# ---- rootfs ---------------------------------------------------------------------------
dd if="$IMG" of="$W/rootfs.img" bs=1M skip=$(( $(part_start 5) / 2048 )) count=$(( ( $(part_end 5) - $(part_start 5) + 1 ) / 2048 + 1 )) status=none
rf() { dbg "cat $1" "$W/rootfs.img"; }
rfls() { dbg "ls $1" "$W/rootfs.img" | tr -s ' \t\n' '\n' | grep -v '^$'; }
rfexists() { dbg "stat $1" "$W/rootfs.img" | grep -q '^Inode:'; }
check 'rf /usr/lib/os-release | grep -q "VERSION_ID=\"22.04\""' "rootfs is Ubuntu 22.04"
check 'rf /etc/fstab | grep -q "PARTUUID=$ROOT_PARTUUID .*/ "' "fstab root by PARTUUID"
check 'rf /etc/fstab | grep -q "PARTUUID=$BOOT_PARTUUID .*/boot"' "fstab /boot by PARTUUID"
check 'rf /etc/hostname | grep -q "$ROOTFS_HOSTNAME"' "hostname $ROOTFS_HOSTNAME"
check 'rf /etc/passwd | grep -q "^$ROOTFS_USER:"' "user $ROOTFS_USER exists"
check 'rf /etc/shadow | grep -q "^root:[!*]"' "root login locked"
REL="$(cat "$OUT/kernel/kernel.release" 2>/dev/null)"
check 'rfls /lib/modules/$REL | grep -q modules.dep' "kernel modules for $REL with modules.dep"
check 'rfls /lib/firmware/rtw88 | grep -q rtw8822c_fw.bin' "RTL8822CE Wi-Fi firmware"
check 'rfls /lib/firmware/rtl_bt | grep -q rtl8822cu_fw.bin' "RTL8822CE Bluetooth firmware"
check 'rfls /usr/share/npu_fw | grep -q boot.img' "NPU firmware set in /usr/share/npu_fw"
for f in /usr/bin/npu_transfer_proxy /usr/bin/upgrade_tool /usr/bin/npu_powerctrl /usr/bin/npu_upgrade /usr/lib/aarch64-linux-gnu/librknn_api.so /usr/include/rknn_api.h /usr/local/sbin/npu-firmware-load /usr/local/sbin/usb-gadget-setup /usr/local/sbin/hdmirx-setup /usr/local/sbin/tinker-first-boot /usr/share/hdmirx/edid-1080p30.bin /etc/default/usb-gadget /etc/systemd/network/20-usb-gadget.network; do
    check 'rfexists $f' "$f"
done
for u in npu-firmware.service npu-transfer-proxy.service usb-gadget.service ssh.service systemd-networkd.service; do
    check 'rfls /etc/systemd/system/multi-user.target.wants | grep -qx $u' "enabled: $u"
done
check 'rfls /etc/systemd/system/sysinit.target.wants | grep -qx tinker-first-boot.service' "enabled: tinker-first-boot.service"
check 'rfls /usr/local/lib/python3.10/dist-packages | grep -q rknnlite' "rknn_toolkit_lite installed for python3.10"
check '[ "$(dbg "stat /usr/local/sbin/usb-gadget-setup" "$W/rootfs.img" | sed -n "s/.*User: *\([0-9]*\).*/\1/p" | head -1)" = 0 ]' "overlay files are root-owned"
check '[ -z "$(rf /etc/machine-id)" ]' "machine-id empty (regenerated on first boot)"
check '! rfls /etc/ssh | grep -q ssh_host_' "no baked-in SSH host keys"

echo
if [ "$fail" = 0 ]; then log "all checks passed for $(basename "$IMG")"; else die "some checks FAILED for $(basename "$IMG")"; fi
