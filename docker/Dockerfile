# Builder image for the Tinker Edge R (RK3399Pro) Ubuntu 22.04 image.
# Everything (U-Boot, kernel, rootfs, disk image) is built inside this container.
FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8 TZ=UTC

RUN apt-get update && apt-get install -y --no-install-recommends \
    # generic build tooling
    build-essential bc bison flex ccache cpio rsync file gawk make patch pkg-config \
    git ca-certificates curl wget xz-utils unzip zstd lz4 bzip2 gzip sudo less vim-tiny \
    python3 python3-dev python3-pip python3-setuptools python3-pyelftools python-is-python3 swig \
    # cross toolchain (Ubuntu 22.04 ships GCC 11)
    gcc-aarch64-linux-gnu g++-aarch64-linux-gnu binutils-aarch64-linux-gnu \
    libssl-dev libncurses-dev libelf-dev dwarves kmod \
    # device tree / u-boot tooling
    device-tree-compiler u-boot-tools \
    # rootfs + image tooling
    debootstrap ubuntu-keyring debian-archive-keyring qemu-user-static binfmt-support \
    gdisk fdisk parted util-linux dosfstools mtools e2fsprogs uuid-runtime bmap-tools time shellcheck \
    && rm -rf /var/lib/apt/lists/*

# Older cross compilers for the legacy trees (2017.09 U-Boot, optional 4.4 kernel).
# GCC 11 is the default; select another with CROSS_GCC_VERSION=9|10 (see scripts/lib.sh).
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc-9-aarch64-linux-gnu gcc-10-aarch64-linux-gnu \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work
