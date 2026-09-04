#!/usr/bin/env bash
# Stage: build the Ubuntu 22.04 arm64 root filesystem.  Runs as root inside the
# privileged builder container (debootstrap needs chroot + mounts; arm64 binaries
# execute through the host's binfmt_misc qemu-aarch64 registration).
#
# The heavy lifting lives in the separate rootfs repository (src/rootfs); this
# stage only wires the build-repo configuration and the kernel/NPU artefacts into it.
#
# Outputs (out/rootfs/):
#   root/               the populated root filesystem tree (root-owned)
#   packages.txt        dpkg selections, BUILD-INFO.txt
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_src rootfs npu
[ "$(id -u)" = 0 ] || die "the rootfs stage must run as root (./build.sh rootfs uses --privileged)"
[ -f "$OUT/kernel/kernel.release" ] || die "kernel not built yet (./build.sh kernel)"

stage_banner "rootfs: Ubuntu $ROOTFS_SUITE $ROOTFS_ARCH"
exec "$SRC/rootfs/mkrootfs.sh" \
    --suite "$ROOTFS_SUITE" --arch "$ROOTFS_ARCH" --mirror "$ROOTFS_MIRROR" \
    --out "$OUT/rootfs" \
    --kernel-out "$OUT/kernel" \
    --npu-src "$SRC/npu" \
    --hostname "$ROOTFS_HOSTNAME" --user "$ROOTFS_USER" --password "$ROOTFS_PASSWORD" \
    --timezone "$ROOTFS_TIMEZONE" --locale "$ROOTFS_LOCALE" \
    --extra-packages "$ROOTFS_EXTRA_PACKAGES" \
    --docs "$TOP/docs" \
    "$@"
