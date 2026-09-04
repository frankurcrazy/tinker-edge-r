#!/usr/bin/env bash
# Stage: assemble the bootable GPT disk image.  Runs as root inside the
# privileged builder container (only because the rootfs tree is root-owned;
# no loop devices or mounts are used).
#
# Layout (512-byte sectors), the standard Rockchip RK3399 raw layout:
#   LBA 64        idbloader.img   (DDR init + miniloader, read by the boot ROM)
#   LBA 16384  p1 uboot   4 MiB   (uboot.img, loaded by the miniloader)
#   LBA 24576  p2 trust   4 MiB   (trust.img: BL31 + BL32)
#   LBA 32768  p3 misc    4 MiB   (Rockchip boot-control block, kept empty)
#   LBA 40960  p4 boot    ext4    (extlinux.conf, Image, dtbs) - "bootable" flag
#              p5 rootfs  ext4    (Ubuntu 22.04)
#
# U-Boot (ASUS 2017.09 tree) tries the Android boot image path first, fails,
# then falls back to distro boot: it scans bootable partitions on SD (mmc 1)
# and eMMC (mmc 0) for /extlinux/extlinux.conf.  See docs/20-boot-flow.md.
#
# Outputs (out/images/):
#   <name>.img[.xz|.zst], <name>.img.sha256, <name>.bmap (if bmaptool present),
#   <name>.partitions.txt, <name>.BUILD-INFO.txt
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[ "$(id -u)" = 0 ] || die "the image stage must run as root (./build.sh image uses --privileged)"
UB="$OUT/u-boot"; KO="$OUT/kernel"; RO="$OUT/rootfs/root"
for f in "$UB/idbloader.img" "$UB/uboot.img" "$UB/trust.img" "$KO/Image" "$KO/kernel.release" "$RO/etc/os-release"; do
    [ -e "$f" ] || die "missing $f - run the uboot/kernel/rootfs stages first"
done
for t in sgdisk mke2fs uuidgen truncate; do command -v "$t" >/dev/null || die "missing tool: $t"; done

REL="$(cat "$KO/kernel.release")"
DATE="$(date -u +%Y%m%d)"
NAME="${IMAGE_NAME}-${DATE}"
IMGDIR="$OUT/images"
WORK="$OUT/image-work"
IMG="$IMGDIR/$NAME.img"
rm -rf "$WORK"; mkdir -p "$WORK/boot/extlinux" "$WORK/boot/dtbs" "$IMGDIR"

stage_banner "image: $NAME (kernel $REL)"

# Stable, per-image partition GUIDs so extlinux.conf and fstab can reference them.
ROOT_PARTUUID="${ROOT_PARTUUID:-$(uuidgen)}"
BOOT_PARTUUID="${BOOT_PARTUUID:-$(uuidgen)}"

# ---- boot partition content ------------------------------------------------------
cp -f "$KO/Image" "$WORK/boot/Image"
cp -f "$KO"/dtbs/*.dtb "$WORK/boot/dtbs/"
cp -f "$KO/config-$REL" "$WORK/boot/config-$REL"
sed -e "s|@KERNEL_RELEASE@|$REL|g" \
    -e "s|@DEFAULT_DTB@|$KERNEL_DEFAULT_DTB|g" \
    -e "s|@ROOT_PARTUUID@|$ROOT_PARTUUID|g" \
    -e "s|@CMDLINE@|$KERNEL_CMDLINE|g" \
    "$CONFIGS/extlinux.conf.in" > "$WORK/boot/extlinux/extlinux.conf"
cat > "$WORK/boot/README.txt" <<EOF
Tinker Edge R boot partition (mounted at /boot on the running system).
  extlinux/extlinux.conf  U-Boot distro-boot menu: kernel, dtb, command line
  Image                   Linux $REL
  dtbs/                   device trees (default: $KERNEL_DEFAULT_DTB)
Generated $(date -u +%FT%TZ) by the tinker-edge-r build repository.
EOF

# fstab inside the rootfs: root by PARTUUID, boot partition on /boot.
cat > "$RO/etc/fstab" <<EOF
# <file system>                            <mount point> <type> <options>                   <dump> <pass>
PARTUUID=$ROOT_PARTUUID  /             ext4   defaults,noatime,errors=remount-ro  0  1
PARTUUID=$BOOT_PARTUUID  /boot         ext4   defaults,noatime                    0  2
EOF

# ---- filesystem images (no loop devices: mke2fs -d) --------------------------------
BOOT_MB="$IMG_BOOT_SIZE_MB"
if [ "${IMG_ROOTFS_SIZE_MB:-0}" -gt 0 ]; then
    ROOT_MB="$IMG_ROOTFS_SIZE_MB"
else
    used_mb="$(du -sxm "$RO" | cut -f1)"
    ROOT_MB=$(( (used_mb * 110 / 100 + IMG_ROOTFS_MARGIN_MB + 3) / 4 * 4 ))
fi
log "boot partition ${BOOT_MB} MiB, rootfs partition ${ROOT_MB} MiB (contents $(du -sxh "$RO" | cut -f1))"

# Boot partition: keep the ext4 feature set conservative (no metadata_csum/64bit)
# so the 2017.09 U-Boot ext4 reader handles it; the kernel does not care.
mke2fs -F -q -t ext4 -L boot -O ^64bit,^metadata_csum,^huge_file \
       -E lazy_itable_init=0,lazy_journal_init=0 -d "$WORK/boot" "$WORK/boot.img" "${BOOT_MB}M"
mke2fs -F -q -t ext4 -L rootfs -E lazy_itable_init=0,lazy_journal_init=0 \
       -d "$RO" "$WORK/rootfs.img" "${ROOT_MB}M"
e2fsck -fn "$WORK/boot.img" >/dev/null || die "boot.img failed fsck"
e2fsck -fn "$WORK/rootfs.img" >/dev/null || die "rootfs.img failed fsck"

# ---- GPT + raw blobs -----------------------------------------------------------------
S_UBOOT=$IMG_SECTOR_UBOOT; S_TRUST=$IMG_SECTOR_TRUST; S_MISC=$IMG_SECTOR_MISC; S_BOOT=$IMG_SECTOR_BOOT
SZ_UBOOT=8192; SZ_TRUST=8192; SZ_MISC=8192            # 4 MiB each
SZ_BOOT=$(( BOOT_MB * 2048 ))
S_ROOT=$(( S_BOOT + SZ_BOOT ))
SZ_ROOT=$(( ROOT_MB * 2048 ))
TOTAL=$(( S_ROOT + SZ_ROOT + 2048 ))                    # room for the backup GPT
rm -f "$IMG"
truncate -s $(( TOTAL * 512 )) "$IMG"

sgdisk -o "$IMG" >/dev/null
sgdisk -n 1:$S_UBOOT:+$SZ_UBOOT -c 1:uboot  -t 1:8301 -u 1:R "$IMG" >/dev/null
sgdisk -n 2:$S_TRUST:+$SZ_TRUST -c 2:trust  -t 2:8301 -u 2:R "$IMG" >/dev/null
sgdisk -n 3:$S_MISC:+$SZ_MISC   -c 3:misc   -t 3:8301 -u 3:R "$IMG" >/dev/null
sgdisk -n 4:$S_BOOT:+$SZ_BOOT   -c 4:boot   -t 4:8300 -u 4:"$BOOT_PARTUUID" -A 4:set:2 "$IMG" >/dev/null
sgdisk -n 5:$S_ROOT:+$SZ_ROOT   -c 5:rootfs -t 5:8305 -u 5:"$ROOT_PARTUUID" "$IMG" >/dev/null

ddin() { dd if="$1" of="$IMG" bs=512 seek="$2" conv=notrunc,sparse status=none; }
ddin "$UB/idbloader.img" 64
ddin "$UB/uboot.img"     "$S_UBOOT"
ddin "$UB/trust.img"     "$S_TRUST"
ddin "$WORK/boot.img"    "$S_BOOT"
ddin "$WORK/rootfs.img"  "$S_ROOT"

# ---- verification + metadata ----------------------------------------------------------
sgdisk -p "$IMG" | tee "$IMGDIR/$NAME.partitions.txt"
sgdisk -v "$IMG" >/dev/null || die "GPT verification failed"
{
    echo "image:          $NAME.img ($(( TOTAL * 512 / 1048576 )) MiB)"
    echo "kernel:         $REL"
    echo "root PARTUUID:  $ROOT_PARTUUID"
    echo "boot PARTUUID:  $BOOT_PARTUUID"
    echo "cmdline:        root=PARTUUID=$ROOT_PARTUUID $KERNEL_CMDLINE"
    echo "default dtb:    $KERNEL_DEFAULT_DTB"
    echo "built:          $(date -u +%FT%TZ)"
    echo "--- u-boot ---";  cat "$UB/BUILD-INFO.txt"
    echo "--- kernel ---";  cat "$KO/BUILD-INFO.txt"
    echo "--- rootfs ---";  cat "$OUT/rootfs/BUILD-INFO.txt" 2>/dev/null || true
} > "$IMGDIR/$NAME.BUILD-INFO.txt"
( cd "$IMGDIR" && sha256sum "$NAME.img" > "$NAME.img.sha256" )
if command -v bmaptool >/dev/null; then bmaptool create -o "$IMGDIR/$NAME.bmap" "$IMG" 2>/dev/null || true; fi

case "$IMG_COMPRESS" in
    xz)   log "compressing with xz";   xz -T0 -6 -f -k "$IMG"; ( cd "$IMGDIR" && sha256sum "$NAME.img.xz" >> "$NAME.img.sha256" ) ;;
    zstd) log "compressing with zstd"; zstd -T0 -19 -f -q "$IMG" -o "$IMG.zst"; ( cd "$IMGDIR" && sha256sum "$NAME.img.zst" >> "$NAME.img.sha256" ) ;;
    none|"") ;;
    *) warn "unknown IMG_COMPRESS=$IMG_COMPRESS, leaving image uncompressed" ;;
esac
rm -rf "$WORK"
# make the outputs readable/deletable by the invoking user
chown -R "$(stat -c %u:%g "$TOP")" "$IMGDIR" 2>/dev/null || true

log "done:"
ls -la "$IMGDIR"/"$NAME".*
