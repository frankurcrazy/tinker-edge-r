# Partition layout

Produced by `scripts/stage-image.sh` (GPT, 512-byte sectors).

| # | name | start LBA | size | content | notes |
|---|---|---|---|---|---|
| - | (raw) | 64 | ~4 MiB max | `idbloader.img` | DDR init + miniloader, read by the boot ROM; not a partition |
| - | (raw) | 0x3f8000 bytes | 32 KiB | U-Boot environment | `CONFIG_ENV_OFFSET` |
| 1 | `uboot` | 16384 (8 MiB) | 4 MiB | `uboot.img` | loaded by the miniloader by name/offset |
| 2 | `trust` | 24576 (12 MiB) | 4 MiB | `trust.img` | BL31 + OP-TEE |
| 3 | `misc` | 32768 (16 MiB) | 4 MiB | zeros | Rockchip boot-control block (`reboot recovery` etc.); U-Boot tolerates it empty |
| 4 | `boot` | 40960 (20 MiB) | `IMG_BOOT_SIZE_MB` (256 MiB) | ext4: `extlinux/extlinux.conf`, `Image`, `dtbs/`, `config-*` | **legacy-bootable attribute set** (`sgdisk -A 4:set:2`), that is what U-Boot's distro scan looks for |
| 5 | `rootfs` | after boot | contents + margin (`IMG_ROOTFS_MARGIN_MB`) | ext4 Ubuntu 22.04 | type `8305` (Linux ARM64 root); grown to the medium on first boot |

Partition unique GUIDs are generated per image (`uuidgen`) and written into
`extlinux.conf` (`root=PARTUUID=`) and `/etc/fstab` (`/` and `/boot`), so the image
boots from eMMC or microSD without device-name assumptions (eMMC is `mmcblk0`, microSD
`mmcblk1` with this kernel's aliases; ASUS's 4.4 kernel numbered them the other way round).

The boot partition is formatted with `-O ^64bit,^metadata_csum,^huge_file` so the
2017.09 U-Boot ext4 reader can parse it; the rootfs uses default jammy ext4 features.

## Compared with the ASUS Debian image

| ASUS partition | ours |
|---|---|
| `uboot`, `trust` (p1, p2) | same offsets and contents (rkbin blobs are newer) |
| `misc` (p3) | same, empty |
| `boot` (p4, 32 MiB, Android boot image with kernel + resource.img/dtb) | ext4 with extlinux (kernel updates = copying files) |
| `recovery` (p5), `backup` (p6) | dropped |
| `userdata` (p7, ext2, mounted at `/boot`, holds ASUS's `config.txt`, `cmdline.txt`, `overlays/`) | dropped; U-Boot only reads it on the Android path |
| `rootfs` (p8) | p5 |

ASUS's `config.txt` interface switches (`intf:uart0=on`, overlays) therefore do not
apply; the equivalent is editing the device tree source or `extlinux.conf`
(no `fdtoverlays` support in this U-Boot generation).

## Sizes

Typical numbers (2024-era package versions): rootfs contents ~1.4 GB (with the extra
tools; ~600 MB base only), image file ~2.2 GB uncompressed, ~600 MB xz.
`IMG_ROOTFS_SIZE_MB` fixes the partition size instead of auto-sizing.
