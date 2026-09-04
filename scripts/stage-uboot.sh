#!/usr/bin/env bash
# Stage: build the ASUS U-Boot (Rockchip 2017.09 tree) and pack the three
# Rockchip boot blobs with rkbin.  Runs inside the builder container.
#
# Outputs (out/u-boot/):
#   idbloader.img   DDR init + miniloader, written raw at sector 64
#   uboot.img       U-Boot proper packed by rkbin loaderimage, "uboot" partition
#   trust.img       BL31 (ATF) + BL32 (OP-TEE) packed by rkbin trust_merger, "trust" partition
#   rk3399pro_loader_*.bin   maskrom loader for rkdeveloptool / upgrade_tool ("db" command)
#   u-boot.bin, u-boot.dtb, .config  for reference
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_src u-boot rkbin
UB="$SRC/u-boot"
RK="$SRC/rkbin"
O="$OUT/u-boot"
B="$O/build"
mkdir -p "$B"

stage_banner "U-Boot: $UBOOT_DEFCONFIG"

# Compiler selection: the 2017.09 tree predates GCC 10; newer compilers need a few
# warnings demoted (they are warnings-as-errors in this tree) and -fcommon for the
# bundled host dtc.  UBOOT_GCC_VERSION=9 or 10 selects an older cross compiler.
CC="${CROSS_COMPILE}gcc"
if [ -n "${UBOOT_GCC_VERSION:-}" ] && command -v "${CROSS_COMPILE}gcc-${UBOOT_GCC_VERSION}" >/dev/null; then
    CC="${CROSS_COMPILE}gcc-${UBOOT_GCC_VERSION}"
fi
HOSTCFLAGS='-Wall -Wstrict-prototypes -O2 -fomit-frame-pointer -fcommon'
KCFLAGS='-Wno-error=address-of-packed-member -Wno-error=stringop-truncation -Wno-error=array-bounds -Wno-error=maybe-uninitialized -Wno-error=misleading-indentation -Wno-error=enum-conversion'

# GNU make >= 4.3 breaks the 2017.09 dts rule (literal '\#include' lines).  The
# tinker-edge-r branch of the U-Boot fork carries the fix; if an unpatched tree is
# used, apply patches/u-boot/*.patch on the fly (leaves the tree modified).
if ! grep -q 'pound)include' "$UB/scripts/Makefile.lib"; then
    for p in "$TOP"/patches/u-boot/*.patch; do
        [ -f "$p" ] || continue
        warn "applying $(basename "$p") to $UB (tree is not on the tinker-edge-r branch)"
        ( cd "$UB" && git apply "$p" ) || die "failed to apply $p"
    done
fi

log "compiler: $CC ($($CC -dumpfullversion 2>/dev/null || true))"
make -C "$UB" O="$B" "$UBOOT_DEFCONFIG"
make -C "$UB" O="$B" -j"$J" CROSS_COMPILE="$CROSS_COMPILE" CC="$CC" \
     HOSTCC=gcc HOSTCFLAGS="$HOSTCFLAGS" KCFLAGS="$KCFLAGS" all

stage_banner "packing boot blobs with rkbin ($(git -C "$RK" rev-parse --short HEAD))"
TEXT_BASE="$(sed -n 's/^CONFIG_SYS_TEXT_BASE=//p' "$B/include/autoconf.mk" | tr -d '\r')"
[ -n "$TEXT_BASE" ] || die "CONFIG_SYS_TEXT_BASE not found"
log "CONFIG_SYS_TEXT_BASE=$TEXT_BASE"

# uboot.img: 4 copies of 1 MiB (matches the 4 MiB "uboot" partition, what ASUS ships)
"$RK/tools/loaderimage" --pack --uboot "$B/u-boot.bin" "$O/uboot.img" "$TEXT_BASE" --size 1024 4

# trust.img: BL31 + BL32 from the RK3399Pro ini (paths inside the ini are rkbin-relative)
( cd "$RK" && rm -f trust.img && "$RK/tools/trust_merger" --size 1024 4 "$RKBIN_TRUST_INI" && mv trust.img "$O/trust.img" )

# idbloader.img: DDR init blob wrapped in the Rockchip "rksd" boot header + miniloader.
# The RK3399Pro boot ROM uses the RK3399 ("RK33") header format.
"$B/tools/mkimage" -n rk3399 -T rksd -d "$RK/$RKBIN_DDR" "$O/idbloader.img"
cat "$RK/$RKBIN_MINILOADER" >> "$O/idbloader.img"

# maskrom loader (for `rkdeveloptool db` / `upgrade_tool ul`), built from the same ini
( cd "$RK" && rm -f rk3399pro_loader_*.bin && "$RK/tools/boot_merger" "$RKBIN_LOADER_INI" >/dev/null && mv rk3399pro_loader_*.bin "$O/" )

cp -f "$B/u-boot.bin" "$B/u-boot.dtb" "$B/.config" "$O/" 2>/dev/null || true
cp -f "$B/.config" "$O/u-boot.config"
sed -n 's/^CONFIG_ENV_\(OFFSET\|SIZE\)=/ENV_\1=/p' "$B/.config" > "$O/env-layout.txt" || true

{
    echo "u-boot commit: $(git -C "$UB" rev-parse HEAD)"
    echo "rkbin commit:  $(git -C "$RK" rev-parse HEAD)"
    echo "ddr:           $RKBIN_DDR"
    echo "miniloader:    $RKBIN_MINILOADER"
    echo "trust ini:     $RKBIN_TRUST_INI"
    echo "compiler:      $CC $($CC -dumpfullversion 2>/dev/null || true)"
} > "$O/BUILD-INFO.txt"

log "artefacts:"
ls -la "$O"/idbloader.img "$O"/uboot.img "$O"/trust.img "$O"/rk3399pro_loader_*.bin
sha256sum "$O"/idbloader.img "$O"/uboot.img "$O"/trust.img > "$O/SHA256SUMS"
