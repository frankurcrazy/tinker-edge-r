# Tinker Edge R Ubuntu 22.04 - documentation index

| document | what it covers |
|---|---|
| [00-overview.md](00-overview.md) | goals, repositories, architecture of the build, what runs where |
| [10-build.md](10-build.md) | prerequisites, `build.sh` stages, configuration in `configs/board.env`, container details, troubleshooting |
| [20-boot-flow.md](20-boot-flow.md) | boot ROM -> miniloader -> U-Boot -> extlinux -> kernel; serial consoles; kernel command line |
| [30-partition-layout.md](30-partition-layout.md) | GPT layout of the image, why, and how it compares with ASUS's |
| [40-kernel-port.md](40-kernel-port.md) | the Tinker Edge R device tree for Linux 6.1: mapping from ASUS's 4.4 DTS, every node explained, config fragments |
| [50-npu.md](50-npu.md) | RK3399Pro NPU: hardware, boot sequence, services, RKNN API / Toolkit Lite usage, verification |
| [60-usb-gadget-typec.md](60-usb-gadget-typec.md) | Type-C port: TCPM/FUSB302, dual role, orientation switch, gadget configuration and examples |
| [70-hdmi-rx.md](70-hdmi-rx.md) | Geekworm X1301 (TC358743) on the CSI connectors: DT, EDID, pipeline, capture examples |
| [80-flashing.md](80-flashing.md) | writing the image to microSD / eMMC, maskrom recovery, U-Boot UMS |
| [90-decisions.md](90-decisions.md) | design decisions with rationale, risks, known limitations, next steps |
| [95-board-notes.md](95-board-notes.md) | facts from the ASUS schematic and from the stock Debian 10 image on a live board |

The `research/` directory keeps raw notes gathered while preparing the port.
