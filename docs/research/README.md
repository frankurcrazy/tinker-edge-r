# Research notes

Raw material gathered while preparing the port (September 2026).  The distilled
versions are in the numbered documents one level up.

* `hid-safe-commands.md` - how read-only commands were typed into the stock image over
  an HDMI/HID capture link (unshifted-character encoding trick), kept for repeatability.
* `toybrick-npu-commit.md` - what the 6.1 tree's "Update Toybrick RK3399ProD with NPU
  support" commit actually changed (basis for the NPU integration reasoning).
* `uboot-config-txt.md` - how ASUS's U-Boot consumes `config.txt` / `cmdline.txt`
  (Android boot path only, partition 7 hard-coded).
