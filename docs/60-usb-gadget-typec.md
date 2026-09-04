# USB Type-C, dual role and the gadget stack

## Hardware

The Type-C receptacle is wired to `usbdrd3_0` (dwc3 at `0xfe800000`, SuperSpeed capable)
through the RK3399 Type-C PHY (`tcphy0`); a Fairchild **FUSB302B** on I2C8 (0x22,
interrupt GPIO1_A2) handles CC detection and USB Power Delivery; VBUS sourcing is
switched by GPIO4_D1 (`VCC5V0_TYPEC0_EN`).  The board is powered from the DC jack, so the
port only ever sinks 5 V for signalling.

## Kernel

| piece | config (fragment `usb-gadget-typec.config`) | device tree |
|---|---|---|
| Type-C class + port manager | `TYPEC`, `TYPEC_TCPM`, `TYPEC_FUSB302`, `TYPEC_DP_ALTMODE`, `USB_ROLE_SWITCH` | `fusb0: usb-typec@22 { compatible = "fcs,fusb302"; ... connector { compatible = "usb-c-connector"; data-role = "dual"; power-role = "dual"; try-power-role = "sink"; ... } }` |
| dual-role controller | `USB_DWC3=y`, `USB_DWC3_DUAL_ROLE=y` | `usbdrd_dwc3_0 { dr_mode = "otg"; usb-role-switch; port { -> fusb0 ports/port@0 } }` |
| cable orientation for SuperSpeed | `PHY_ROCKCHIP_TYPEC` (this tree supports `orientation-switch`) | `tcphy0 { orientation-switch; port { -> connector ports/port@0 } }` |
| VBUS | | `vbus-supply = <&vbus_typec>` (fixed regulator, GPIO4_D1) |
| gadget core | `USB_GADGET`, `USB_LIBCOMPOSITE`, `USB_CONFIGFS` + every `USB_CONFIGFS_*` function, all `USB_F_*` built in | |
| legacy gadgets | `g_ether`, `g_serial`, `g_mass_storage`, `g_multi`, `g_hid`, `g_midi`, `g_audio`, `g_webcam`, `g_ncm`, `g_zero`, `gadgetfs`, `g_ffs`, `raw_gadget`, ... as modules | mutually exclusive with the configfs gadget |

What happens on the wire:

1. TCPM (the FUSB302 driver) negotiates the data role from the CC lines: attached to a
   PC → the board becomes **UFP/device**; attached to a USB device or OTG cable →
   **DFP/host** (and VBUS is switched on through `vbus_typec`).
2. TCPM calls the dwc3 **role switch**, which flips the controller between xHCI host
   and peripheral mode, and the **orientation switch** on `tcphy0`, which routes the
   SuperSpeed lanes for the cable orientation.
3. With nothing attached the controller idles in peripheral mode
   (`role-switch-default-mode` default), so the gadget is ready when a host plugs in.

Inspect at runtime:

```sh
ls /sys/class/typec/                          # port0, port0-partner when attached
cat /sys/class/typec/port0/{data_role,power_role,orientation}
cat /sys/class/udc/fe800000.dwc3/state        # not attached / configured
cat /sys/kernel/debug/usb/fe800000.dwc3/mode  # host / device
dmesg | grep -iE 'fusb302|tcpm|dwc3|typec'
```

## The gadget service

`usb-gadget.service` runs `/usr/local/sbin/usb-gadget-setup start` at boot and builds a
composite gadget through configfs, configured in **`/etc/default/usb-gadget`**:

```sh
GADGET_FUNCTIONS="ncm acm"      # default: CDC-NCM Ethernet + CDC-ACM serial
```

| function | what you get on the host |
|---|---|
| `ncm` / `ecm` / `eem` / `rndis` | a USB network adapter; the board is `192.168.7.2/24` and runs a DHCP server for the host (`systemd-networkd`, `20-usb-gadget.network`).  `ssh tinker@192.168.7.2`.  Use `rndis` for Windows 10 and older (`ncm` works on Linux, macOS, Windows 11) |
| `acm` | a serial port (`/dev/ttyACM0` on the host) with a login prompt (`serial-getty@ttyGS0`) |
| `mass_storage` | a USB drive backed by `GADGET_MS_FILE` (file or block device) |
| `hid` | a USB keyboard (`/dev/hidg0` on the board, write 8-byte reports) |
| `uac2` | a USB sound card (48 kHz stereo both directions) |
| `midi` | a USB MIDI interface |
| `ffs` | FunctionFS at `/dev/usb-ffs/tinker` for daemons like `adbd`; bind manually |

```sh
usb-gadget-setup status | stop | start | restart
systemctl restart usb-gadget            # after editing /etc/default/usb-gadget
```

The script derives stable MAC addresses and the serial number from the SoC serial
(`/proc/device-tree/serial-number`), sets `bcdUSB 0x0320` so SuperSpeed descriptors are
offered, and binds to `fe800000.dwc3`.

### Using a legacy gadget instead

Stop the configfs gadget first, then load one module:

```sh
systemctl stop usb-gadget
modprobe g_mass_storage file=/path/to/disk.img removable=1
# or: modprobe g_serial | g_ether | g_multi | g_hid | g_midi | g_audio ...
```

### Host mode

Plug a USB device (or an OTG adapter) into the Type-C port: TCPM switches dwc3 to host,
`lsusb` shows it, VBUS is provided.  The gadget stays configured and is exposed again as
soon as the port returns to device mode.

## Known limitations

* DisplayPort alternate mode over Type-C is not enabled (`cdn_dp` disabled): this tree's
  cdn-dp driver expects an extcon provider that the TCPM stack does not offer.  HDMI is
  the display output.
* PD power negotiation is limited to 5 V profiles by design (the board is DC-jack powered).
* Not yet tested on hardware: orientation handling and SuperSpeed enumeration
  ([90-decisions.md](90-decisions.md)).
