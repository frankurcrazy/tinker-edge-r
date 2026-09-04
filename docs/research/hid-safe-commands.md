# Typing commands into the stock image over an HID emulator

The stock ASUS image was inspected through an HDMI capture + USB HID gadget link.  The
HID path dropped every **shifted** character (`| > * _ & $ ( ) ~ # !` and upper case).
Workaround: encode the command with printf octal escapes and run it through backtick
substitution, which only needs unshifted keys:

```sh
eval `printf 'ls /usr/bin \174 grep -i npu'`      # \174 = '|'
eval `printf 'cat /proc/device-tree/usb1/dwc3\100fe900000/dr\137mode'`   # \100 = '@', \137 = '_'
```

`hidenc.py` (kept in the session's scratch directory) converted arbitrary commands into
this form: every character outside `a-z 0-9 - = [ ] \ ; ' , . / \` space` becomes `\ooo`.

Commands used (all read-only): `cat /proc/version /proc/cmdline`, `lsblk`,
`ls -l /dev/disk/by-partlabel`, `mount`, `df`, `cat /boot/config.txt`, `ls /usr/bin`,
`cat /usr/bin/npu-image.sh`, `grep -n npu /etc/init.d/*.sh`, `dpkg -S`, `strings`-like
`grep -a -o` on `npu_powerctrl`, `lsusb`, `pgrep -af npu`, `npu_transfer_proxy devices`.
