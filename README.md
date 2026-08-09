# USBTrail

Process-oriented USB tracer for Linux.

Runs a command and produces a single timeline of what that command and its children
actually did with USB devices — across device re-enumeration.

usbmon and Wireshark are tcpdump for USB: they capture a bus and show everything on it.
USBTrail is strace for USB — it follows one command. You filter by process, not by
device address.

```
usbtrail -- ./flash.sh
```

```
0.012 st-flash(4473) open 001/004 [0483:3748 ST-LINK]
0.014 st-flash(4473) CTRL OUT len=16
1.204 st-flash(4473) BULK OUT ep=0x02 len=1024 ×248 (1.20s–3.88s, 203 KiB)
2.007 [unattributed] INTR IN ep=0x81 len=8 (001/004, session device)

3.881 USB REMOVE 001/004 [0483:3748] port 1-1.4
4.402 USB ADD 001/007 [0483:df11 STM32 BOOTLOADER] port 1-1.4
↳ probable re-enumeration (same port, +521ms)

4.410 dfu-util(4491) open 001/007
```

Built from:

- **usbmon** — USB traffic
- **eBPF** — exact URB-to-process attribution
- **netlink uevent + sysfs** — device add, remove, port topology

Transfers that can't be attributed are marked `[unattributed]`, never guessed.

**Scope:** Linux, USB, command + descendants, hotplug tracking, pcapng export for Wireshark.
