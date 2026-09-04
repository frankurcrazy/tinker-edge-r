#!/usr/bin/env bash
# Stage: build the Rockchip 6.1 vendor kernel for the Tinker Edge R.
# Runs inside the builder container.
#
# Outputs (out/kernel/):
#   Image                    arm64 kernel image (uncompressed)
#   dtbs/*.dtb               board device trees (KERNEL_DTBS)
#   modules/lib/modules/...  stripped modules tree (modules_install)
#   config, System.map, kernel.release, BUILD-INFO.txt
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_src kernel
K="$SRC/kernel"
O="$OUT/kernel"
B="$O/build"
mkdir -p "$B" "$O/dtbs"

export ARCH=arm64
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-tinker}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-tinker-edge-r-builder}"
export CROSS_COMPILE
if command -v ccache >/dev/null; then
    export CROSS_COMPILE_CCACHE="ccache $CROSS_COMPILE"
    MAKE_CC=(CC="ccache ${CROSS_COMPILE}gcc")
else
    MAKE_CC=()
fi

stage_banner "kernel: $(git -C "$K" describe --always --dirty 2>/dev/null) ($KERNEL_DEFCONFIG)"

# The board DTS lives in the kernel repository (branch tinker-edge-r).  If a tree
# without it is used, fall back to the staging copy kept in this repository.
DTS_DIR="$K/arch/arm64/boot/dts/rockchip"
for f in "$TOP"/kernel/*.dts "$TOP"/kernel/*.dtsi; do
    [ -f "$f" ] || continue
    if [ ! -f "$DTS_DIR/$(basename "$f")" ]; then
        warn "kernel tree lacks $(basename "$f"); copying it from $TOP/kernel (use the tinker-edge-r branch instead)"
        cp -f "$f" "$DTS_DIR/"
    fi
done
for d in $KERNEL_DTBS; do
    dtb="$(basename "$d")"
    if ! grep -q "$dtb" "$DTS_DIR/Makefile"; then
        warn "adding $dtb to $DTS_DIR/Makefile"
        printf 'dtb-$(CONFIG_ARCH_ROCKCHIP) += %s\n' "$dtb" >> "$DTS_DIR/Makefile"
    fi
done

# 1. defconfig + fragments
make -C "$K" O="$B" "$KERNEL_DEFCONFIG"
FRAGS=()
for f in $KERNEL_FRAGMENTS; do
    [ -f "$CONFIGS/kernel/$f" ] || die "fragment not found: $CONFIGS/kernel/$f"
    FRAGS+=("$CONFIGS/kernel/$f")
done
if [ ${#FRAGS[@]} -gt 0 ]; then
    log "merging fragments: $KERNEL_FRAGMENTS"
    ( cd "$K" && KCONFIG_CONFIG="$B/.config" scripts/kconfig/merge_config.sh -O "$B" -m "$B/.config" "${FRAGS[@]}" )
    make -C "$K" O="$B" olddefconfig
    if ! check_config_fragments "$B/.config" "${FRAGS[@]}"; then
        die "some fragment options were not honoured; see warnings above"
    fi
fi

# 2. build
make -C "$K" O="$B" -j"$J" "${MAKE_CC[@]}" LOCALVERSION="$KERNEL_LOCALVERSION" Image dtbs modules

# 3. install
rm -rf "$O/modules"
make -C "$K" O="$B" -j"$J" LOCALVERSION="$KERNEL_LOCALVERSION" \
     INSTALL_MOD_PATH="$O/modules" INSTALL_MOD_STRIP=1 modules_install
REL="$(cat "$B/include/config/kernel.release")"
cp -f "$B/arch/arm64/boot/Image" "$O/Image"
for d in $KERNEL_DTBS; do
    cp -f "$B/arch/arm64/boot/dts/$d" "$O/dtbs/"
done
cp -f "$B/.config" "$O/config-$REL"
cp -f "$B/System.map" "$O/System.map-$REL"
echo "$REL" > "$O/kernel.release"
rm -f "$O/modules/lib/modules/$REL/build" "$O/modules/lib/modules/$REL/source"
{
    echo "kernel commit:  $(git -C "$K" rev-parse HEAD)"
    echo "release:        $REL"
    echo "defconfig:      $KERNEL_DEFCONFIG"
    echo "fragments:      $KERNEL_FRAGMENTS"
    echo "dtbs:           $KERNEL_DTBS"
    echo "compiler:       $(${CROSS_COMPILE}gcc -dumpfullversion)"
} > "$O/BUILD-INFO.txt"

log "kernel $REL built:"
ls -la "$O/Image" "$O"/dtbs/*.dtb
log "modules: $(find "$O/modules" -name '*.ko' | wc -l)"
