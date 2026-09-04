# Building

## Host requirements

* Linux x86_64 host with Docker (tested: Ubuntu 24.04, Docker 29) and the user in the `docker` group.
* `git` and the `repo` launcher (`https://gerrit.googlesource.com/git-repo`; on Ubuntu: `apt install repo` or the launcher script in `~/bin`).
* **binfmt_misc with qemu-user-static registered for aarch64** on the host kernel, with
  the `F` (fix binary) flag.  Docker containers run arm64 binaries through the host
  registration; check with:

  ```sh
  cat /proc/sys/fs/binfmt_misc/qemu-aarch64   # must say "enabled" and flags containing F
  docker run --rm --platform linux/arm64 ubuntu:22.04 uname -m   # arm64
  ```
  On Ubuntu: `apt install qemu-user-static binfmt-support` registers it; on other
  distributions `docker run --privileged --rm tonistiigi/binfmt --install arm64` does.
* Disk: about 6 GB for sources, 8 GB for build output; RAM: 4 GB+; the kernel build
  uses all cores (`J=` to limit).

## Stages

```sh
./build.sh builder     # docker build -t tinker-edge-r-builder:latest docker/
./build.sh fetch       # repo init -u <origin of this checkout> -b <branch>; repo sync -c
./build.sh uboot       # out/u-boot/
./build.sh kernel      # out/kernel/
./build.sh rootfs      # out/rootfs/root/   (privileged container, root-owned tree)
./build.sh image       # out/images/        (privileged container)
./build.sh all         # uboot kernel rootfs image
./build.sh shell       # interactive shell in the container (PRIVILEGED=1 ./build.sh shell for root)
./build.sh clean       # remove out/ (uses the container to delete root-owned files)
```

Stages are independent once their inputs exist; re-run only what changed.  Every stage
writes a `BUILD-INFO.txt` with the commit ids and tool versions that produced it.

`fetch` uses the `origin` remote of this checkout as manifest URL (override with
`REPO_MANIFEST_URL=...`), so a fork of this repository automatically syncs its own
manifest.  `REPO_GROUPS=legacy ./build.sh fetch` also syncs ASUS's 4.4 kernel into
`src/kernel-legacy` for reference.

Without `repo`, clone the projects by hand into `src/` at the revisions listed in
`default.xml` (`git clone --depth 1 -b <revision> <url> src/<path>`).

## Configuration

Everything lives in [`configs/board.env`](../configs/board.env) and can be overridden
from the environment, for example:

```sh
ROOTFS_USER=frank ROOTFS_PASSWORD='s3cret' ROOTFS_HOSTNAME=edge ./build.sh rootfs image
J=8 UBOOT_GCC_VERSION=10 ./build.sh uboot
KERNEL_FRAGMENTS="tinker-edge-r.config usb-gadget-typec.config" ./build.sh kernel   # no camera stack
IMG_COMPRESS=none IMG_BOOT_SIZE_MB=128 ./build.sh image
```

| group | knobs |
|---|---|
| toolchain | `CROSS_COMPILE`, `UBOOT_GCC_VERSION` (9/10/11), `J` |
| kernel | `KERNEL_DEFCONFIG`, `KERNEL_FRAGMENTS`, `KERNEL_DTBS`, `KERNEL_DEFAULT_DTB`, `KERNEL_LOCALVERSION`, `KERNEL_CMDLINE` |
| U-Boot | `UBOOT_DEFCONFIG`, `RKBIN_DDR`, `RKBIN_MINILOADER`, `RKBIN_LOADER_INI`, `RKBIN_TRUST_INI` |
| rootfs | `ROOTFS_SUITE`, `ROOTFS_MIRROR`, `ROOTFS_HOSTNAME`, `ROOTFS_USER`, `ROOTFS_PASSWORD`, `ROOTFS_TIMEZONE`, `ROOTFS_LOCALE`, `ROOTFS_EXTRA_PACKAGES` |
| image | `IMAGE_NAME`, `IMG_BOOT_SIZE_MB`, `IMG_ROOTFS_SIZE_MB` (0 = auto), `IMG_ROOTFS_MARGIN_MB`, `IMG_COMPRESS` (xz/zstd/none) |

Kernel configuration = `rockchip_linux_defconfig` from the kernel tree (Toybrick,
PREEMPT_RT) + the fragments in `configs/kernel/` merged with the kernel's
`merge_config.sh`.  The kernel stage fails if a fragment option did not end up in
the final `.config` (usually a missing dependency), so fragments are always honoured or
the build stops.

Package selection for the rootfs is in the rootfs repository
(`src/rootfs/config/packages-*.txt`), the overlay (`src/rootfs/overlay/`) holds every
config file and service.

## The container

`docker/Dockerfile`: Ubuntu 22.04 with `gcc-aarch64-linux-gnu` 11 (default, used for
the 6.1 kernel and U-Boot), `gcc-9`/`gcc-10` cross compilers (for the legacy trees),
`debootstrap`, `qemu-user-static`, `gdisk`/`e2fsprogs`/`dosfstools`, `u-boot-tools`,
`device-tree-compiler`, `bmap-tools`, `ccache`.

* `uboot`, `kernel`, `shell` run as the invoking user (`--user uid:gid`), so
  `out/u-boot` and `out/kernel` are owned by you.
* `rootfs` and `image` run `--privileged` as root (debootstrap needs `chroot`, `mount`,
  `mknod`; the image stage reads the root-owned tree).  `out/rootfs` is root-owned;
  `./build.sh clean` removes it through the container.
* The workspace is bind-mounted at the same absolute path inside the container, so
  paths in logs are valid on the host.  `ccache/` under the workspace is reused across builds.

## Troubleshooting

* `debootstrap` fails with `Exec format error` → binfmt_misc is not registered on the host (see above).
* U-Boot `dtc ... syntax error` for boards like `rk3188-radxarock` → the tree lacks the
  make 4.3 fix; the stage applies `patches/u-boot/*.patch` automatically when the
  `tinker-edge-r` branch is not used.
* Kernel fails on `firmware/rtl_bt/rtl8723d_fw.bin` → the Toybrick defconfig links
  firmware blobs that are not in git; `configs/kernel/tinker-edge-r.config` clears
  `CONFIG_EXTRA_FIRMWARE`, so this only happens when the fragment is not merged.
* `repo sync` fails on a pinned SHA with `clone-depth` → GitHub allows fetching any
  reachable SHA; if a mirror does not, drop `clone-depth` in `default.xml`.
* Root-owned leftovers in `out/` → `./build.sh clean`.
