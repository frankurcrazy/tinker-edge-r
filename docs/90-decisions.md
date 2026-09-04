# Decisions, risks, next steps

## Decisions

| decision | alternatives | why |
|---|---|---|
| **Linux 6.1 Rockchip vendor kernel** (`TB-RK3399ProD-Kernel-6.1`, branch `develop-6.1-rt45`) as the base | ASUS's 4.4.194 kernel (works out of the box with the NPU); mainline | 4.4 is EOL, Ubuntu 22.04 userspace expects newer kernel features (cgroup v2, newer BPF/netfilter) and the fork was already chosen by the project owner; mainline has no NPU-related integration and no vendor ISP/VPU.  The 6.1 tree keeps everything the NPU userspace needs and had already been booted on a sibling RK3399Pro board. |
| keep `CONFIG_PREEMPT_RT=y` from the base defconfig | build a non-RT (`PREEMPT`) kernel with a fragment | it is the configuration the tree's maintainer tests (branch name `develop-6.1-rt45`, README).  A fragment with `# CONFIG_PREEMPT_RT is not set` / `CONFIG_PREEMPT=y` switches it off if throughput matters more than latency. |
| device tree written as a new `rk3399pro-tinker-edge-r.dtsi` instead of patching the Toybrick files | overlaying ASUS's 4.4 DTS onto `rk3399pro-toybrick.dtsi` | the boards differ in most GPIO assignments and every regulator voltage; a self-contained file with the ASUS values is easier to audit ([40-kernel-port.md](40-kernel-port.md)) |
| Type-C through upstream TCPM (`fcs,fusb302`) with a connector node and the `tcphy0` orientation switch | Toybrick's minimal pattern (no connector, no orientation switch) | the Toybrick node uses `fairchild,fusb302`, which no driver in the 6.1 tree binds to, so its Type-C likely never switched roles; the EVB file in the same tree shows the full pattern and the tree's PHY driver implements `orientation-switch`.  This is the requested "typec device class + dual role". |
| `cdn_dp` disabled | enable DP altmode | needs an extcon bridge from TCPM that the tree lacks; Toybrick disables it too |
| extlinux (U-Boot distro boot) instead of ASUS's Android boot image + `resource.img` | Rockchip `boot.img` packing | the same U-Boot generation boots the Toybrick 6.1 kernel this way (`make_toybrick_boot_linux.sh`), kernel/DTB updates are plain file copies, multiple boot entries (CSI1 variant, rescue) |
| ASUS's U-Boot unmodified except one build fix | mainline U-Boot | ASUS's tree carries the board's DDR/PMIC setup and UMS features; one commit fixes the GNU make 4.3 incompatibility of the 2017.09 kbuild |
| rkbin blobs: `rk3399pro_ddr_800MHz_v1.30`, `miniloader_v1.26`, `bl31_v1.35`, `bl32_v2.12` (rkbin master pinned) | ASUS's original blob set | rkbin's own `RK3399PROMINIALL.ini` selects the 800 MHz DDR blob for LPDDR4-1600; ASUS did not publish their exact blobs.  If DDR init misbehaves, the 666/933 MHz variants and older tags are one manifest change away. |
| NPU userspace from `airockchip/RK3399Pro_npu` (firmware, proxy, API, 1.7.5) + `upgrade_tool`/`npu_powerctrl` from ASUS's public `TinkerBoard2/debian` overlay | binaries extracted from the ASUS Debian image | all sources are public git repositories at pinned commits; the firmware, proxy and API come from one release so their versions match; `npu_powerctrl` is byte-identical in name/size/version (`V1.1`) to what the stock Tinker Edge R image runs |
| separate `tinker-edge-r-rootfs` repository | rootfs scripts inside the build repo | requested; the userspace definition (packages, services, vendored binaries) evolves independently of the build plumbing |
| `repo` manifest | git submodules | fits the Rockchip/Android-style trees, one file lists every revision, shallow sync; `repo manifest -r` re-pins |
| everything in Docker; privileged only for `rootfs`/`image` | rootless with `mmdebstrap`/fakeroot | debootstrap + chroot under qemu binfmt is the most predictable path; no loop devices are ever needed (`mke2fs -d`) |
| GCC 11 for both trees | Linaro 6.3.1 (what ASUS/Rockchip used) | Linaro's download site no longer serves the archive; GCC 11 builds the 6.1 kernel cleanly and U-Boot with a handful of warnings demoted; GCC 9/10 are installed for experiments (`UBOOT_GCC_VERSION`) |
| firmware files fetched from linux-firmware at build time with sha256 pins | `linux-firmware` package (~900 MB installed) | minimal image |
| kernel console on UART0 (fiq debugger, 115200) | UART2 (`ttyS2`, Rockchip default 1.5 Mbaud) | UART0 is what ASUS exposes on the 40-pin header and what their image uses; U-Boot itself still logs on UART2 |
| default user `tinker`/`tinker` with passwordless sudo, SSH password login | no default account | development-board convention; change at first login (`passwd`) or set `ROOTFS_PASSWORD` when building |

## Risks / not yet verified on hardware

Ordered by impact.  Everything below compiled and was checked statically; the image has
not been booted on a Tinker Edge R yet.

1. **DDR / boot blobs**: rkbin master blobs instead of ASUS's originals.  Symptom of a
   mismatch: no U-Boot output on UART2 / no boot.  Fallback: ASUS's Debian image on the
   eMMC provides a working U-Boot which boots this image from microSD anyway
   ([80-flashing.md](80-flashing.md)).
2. **Boot partition readability by the 2017.09 U-Boot**: ext4 without `metadata_csum`/`64bit`
   was chosen for that reason; if `sysboot` cannot read it, reformat as ext2 (Toybrick used
   ext2) by changing `mke2fs -t ext4` to `-t ext2` in `scripts/stage-image.sh`.
3. **NPU bring-up**: `npu_powerctrl` GPIOs 35/56 and the debugfs clock hooks are inherited
   from the vendor tooling; the DTS keeps those GPIOs unclaimed.  Verify with `npu-status`;
   `/tmp/npu.log` shows where the maskrom sequence stops.
4. **Type-C orientation switch / SuperSpeed gadget**: EVB pattern, untested here.
   Fallback documented in [40-kernel-port.md](40-kernel-port.md).
5. **Wi-Fi**: `vcc_wifi` (GPIO2_D3) as `vpcie3v3-supply` must be high before PCIe link
   training; if the RTL8822CE is not enumerated (`lspci`), check `dmesg | grep pcie` and
   consider `regulator-boot-on` timing or the PERST# GPIO (GPIO0_B4).
6. **HDMI-RX pipeline**: vendor rkisp1 + tc35874x, format propagation via `media-ctl`
   ([70-hdmi-rx.md](70-hdmi-rx.md)).
7. **VDD_LOG**: left as programmed by U-Boot (PWM2), same as the Toybrick port.
8. RT kernel + gadget/ISP drivers: the tree's maintainer fixed several RT issues; new ones
   may surface under load (switch to `PREEMPT` if so).

## Next steps

1. Flash a microSD card, attach the UART0 console, boot, and go through
   `npu-status`, `usb-gadget-setup status`, `lspci`, `hciconfig`, `hdmirx-setup status`.
2. Pin the manifest to the tested commits (`repo manifest -r -o default.xml`) and tag.
3. Optional improvements: systemd sleep hook to reload the NPU after suspend; DP altmode
   via an extcon shim; `fdtoverlays` support would need a newer U-Boot.
