# USBTrail

USBTrail is a process-oriented USB tracing tool for Linux.

It runs a command and correlates its process tree with USB traffic and device hotplug events, producing a single timeline of what the command actually did with USB devices.

```bash
usbtrail -- ./flash.sh
```

Example output:

```text
0.012  st-flash(4473)  open   001/004 [0483:3748 ST-LINK]
0.014  st-flash(4473)  CTRL   OUT  len=16
1.204  st-flash(4473)  BULK   OUT  ep=0x02 len=1024 ×248

3.881  USB REMOVE       001/004 [0483:3748]
4.402  USB ADD          001/007 [0483:df11 STM32 BOOTLOADER]
       ↳ probable re-enumeration

4.410  dfu-util(4491)   open   001/007
```

USBTrail combines:

* `usbmon` for USB traffic
* process tracing for command attribution
* `udev`/sysfs for device add, remove, and re-enumeration events

The goal is not to replace Wireshark, but to answer a different question:

**What USB activity was caused by this command?**

Initial scope: Linux, USB, command + child processes, hotplug tracking, and exportable captures.
