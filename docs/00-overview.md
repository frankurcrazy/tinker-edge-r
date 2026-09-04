# Overview

## Goal

A minimal, reproducible **Ubuntu 22.04 (jammy, arm64)** image for the ASUS Tinker Edge R
that keeps the board's special hardware usable:

| requirement | how it is met |
|---|---|
| NPU support | Rockchip 6.1 vendor kernel keeps the USB/GPIO/debugfs facilities the NPU tools need; the rootfs ships the firmware, `npu_transfer_proxy`, `librknn_api`, RKNN Toolkit Lite and systemd units that load the NPU at boot ([50-npu.md](50-npu.md)) |
| Type-C device class + full USB gadget | TCPM + FUSB302 + dwc3 dual role + orientation switch in the device tree; every gadget function enabled; a configfs gadget service ([60-usb-gadget-typec.md](60-usb-gadget-typec.md)) |
| dual-role switch for dwc3 and FUSB302 | `usb-role-switch` graph between the FUSB302 connector and `usbdrd_dwc3_0` ([40-kernel-port.md](40-kernel-port.md)) |
| Geekworm X1301 HDMI RX | TC358743 node on CSI0 (or CSI1 via a second DTB), vendor rkisp1 pipeline, EDID + setup helper ([70-hdmi-rx.md](70-hdmi-rx.md)) |
| separate repositories | `repo` manifest in this repository ties kernel, U-Boot, rootfs, Rockchip blobs and NPU userspace together at pinned revisions |
| container build | every stage runs in `docker/Dockerfile`'s image; only `git`/`repo`/`docker` are needed on the host |
| documentation | this `docs/` tree, also installed on the device |

## Repositories

```
tinker-edge-r/                 <- this repository = workspace root
├── default.xml                repo manifest (pinned revisions)
├── build.sh                   host-side driver: builder | fetch | uboot | kernel | rootfs | image | all | shell
├── docker/Dockerfile          Ubuntu 22.04 builder: GCC 9/10/11 aarch64 cross, debootstrap, qemu-user-static, gdisk, ...
├── scripts/                   stage-*.sh run inside the container, lib.sh shared helpers
├── configs/                   board.env (all knobs), kernel/*.config fragments, extlinux.conf.in
├── kernel/                    staging copy of the Tinker Edge R DTS (canonical copy: kernel branch)
├── patches/                   the same changes as patches (kernel DTS, U-Boot make 4.3 fix)
├── docs/                      this documentation
└── src/  (after fetch)        kernel/ u-boot/ rkbin/ npu/ rootfs/ [kernel-legacy/]   (git-ignored)
    out/ (after build)         u-boot/ kernel/ rootfs/ images/                          (git-ignored)
```

| project (manifest path) | repository / branch | why it is separate |
|---|---|---|
| `src/kernel` | `frankurcrazy/TB-RK3399ProD-Kernel-6.1`, branch `tinker-edge-r` | large vendor tree; board support is a normal kernel commit series on top of the Toybrick port |
| `src/u-boot` | `frankurcrazy/tinker-edge-r-debian-u-boot`, branch `tinker-edge-r` | ASUS's bootloader, used as-is plus one build fix |
| `src/rkbin` | `rockchip-linux/rkbin` | Rockchip's binary blobs (DDR init, miniloader, BL31, OP-TEE) and packing tools |
| `src/npu` | `airockchip/RK3399Pro_npu` | NPU firmware (USB set), `npu_transfer_proxy`, `librknn_api`, docs |
| `src/rootfs` | `frankurcrazy/tinker-edge-r-rootfs` | everything that describes the userspace: package lists, overlay, services, vendored NPU tools |
| `src/kernel-legacy` (group `legacy`, not synced by default) | `frankurcrazy/tinker-edge-r-debian-kernel` | ASUS's original 4.4 kernel, kept only as reference |

Why `repo` and not git submodules: the trees come from the Rockchip/Android ecosystem
where `repo` manifests are the norm, the manifest documents every revision in one file,
`repo sync -c` with `clone-depth` keeps the checkout small, and the manifest can be
re-pinned with `repo manifest -r`.  Nothing prevents cloning the projects by hand at the
revisions in `default.xml` (see [10-build.md](10-build.md)).

## Build pipeline

```
 src/u-boot + src/rkbin ──stage-uboot──▶ out/u-boot/{idbloader.img,uboot.img,trust.img,rk3399pro_loader_*.bin}
 src/kernel + configs/kernel/*.config ──stage-kernel──▶ out/kernel/{Image,dtbs/,modules/}
 src/rootfs + out/kernel + src/npu ──stage-rootfs (privileged)──▶ out/rootfs/root/
 all of the above + configs/extlinux.conf.in ──stage-image (privileged)──▶ out/images/<name>.img.xz
```

No loop devices are used: partitions are produced with `mke2fs -d` and written into the
GPT image with `dd`.  The privileged container is only needed for `debootstrap`/`chroot`
(mounts, device nodes) and to read the root-owned rootfs tree.

## What runs on the board

```
boot ROM → idbloader (DDR init + miniloader) → trust.img (BL31/OP-TEE) → uboot.img (ASUS U-Boot 2017.09)
       → distro boot: /extlinux/extlinux.conf on the "boot" partition → Image + rk3399pro-tinker-edge-r.dtb
       → Ubuntu 22.04 (systemd, networkd, ssh)
            ├─ npu-firmware.service: npu_powerctrl + upgrade_tool push the NPU firmware over USB
            ├─ npu-transfer-proxy.service: RKNN API transport
            ├─ usb-gadget.service: configfs gadget on the Type-C port (NCM Ethernet + ACM serial by default)
            └─ tinker-first-boot.service: grow rootfs, ssh keys, machine-id (once)
```
