# USBTrail — Roadmap

Process-oriented USB tracer for Linux.

```bash
usbtrail -- ./flash.sh
```

Follows one command and all its children, and shows what they did on USB — across device
re-enumeration. Filters by process, not by device address.

**Stack:** C++17 + libbpf/CO-RE. Spikes in Python + bcc/bpftrace.

**Requirements:** Linux 5.7 or newer, kernel BTF (`CONFIG_DEBUG_INFO_BTF`), cgroup v2, root.
Hard-fail at startup with a clear message if `/sys/kernel/btf/vmlinux` is unreadable — there is
no non-BTF mode.

```
command + descendants
        │
   eBPF: usbdev_ioctl → usb_submit_urb
        │  (urb pointer + PID, exact)
        ▼
    correlator ◄──── usbmon /dev/usbmon0  (URB data, id = urb pointer)
        │       ◄──── netlink uevent + sysfs  (hotplug, port topology)
        │
   ┌────┴────┐
   ▼         ▼
timeline   pcapng
```

---

## v0.0 — Spikes

Throwaway scripts. Verify on two kernels, then delete the code.

- **Main experiment:** a probe on `usbdev_ioctl` → `usb_submit_urb` yields a URB pointer that
  matches `id` in the usbmon stream.
- Confirm `USBDEVFS_SUBMITURB32` from 32-bit userspace reaches the same probe chain.
- Determine whether fentry attaches to `usbdev_ioctl` or a kprobe is required.
- Confirm `clone3(CLONE_INTO_CGROUP)` works.

```bash
uname -r
sudo modprobe usbmon && ls -l /dev/usbmon*
test -r /sys/kernel/btf/vmlinux
grep -c usb_submit_urb /proc/kallsyms
grep -c usbdev_ioctl /proc/kallsyms
bpftool btf dump file /sys/kernel/btf/vmlinux format c | grep -c usb_dev_state
sudo modprobe dummy_hcd raw_gadget && ls -l /dev/raw-gadget
clang --version
```

**Done:** 
- BTF available ✅
- usbdev_ioctl present in BTF ✅
- usb_submit_urb present in BTF ✅
- fentry/kfunc attaches to usbdev_ioctl ✅
- fentry/kfunc attaches to usb_submit_urb ✅
- kretfunc attaches to usbdev_ioctl ✅
- USBDEVFS_SUBMITURB reaches usbdev_ioctl ✅
- usb_submit_urb executes inside the same usbdev_ioctl call window ✅
- ENTRY → SUBMIT → RETURN observed on the same TID ✅
- usbdev_ioctl returns success ✅ 
- struct urb * seen at usb_submit_urb matches usbmon id ✅
- controlled USB transfer completes successfully ✅

_Other_
- Set-up github ✅ 
- Set-up dev environment




**NOTE — settled by desk research, no spike needed**
usbmon's `id` is the URB pointer, carried from submit to callback; timestamps come from
`ktime_get_real_ts64` (CLOCK_REALTIME); `len_urb` vs `len_cap` reveals truncation;
`MON_IOCG_STATS` reports drops and `MON_IOCT_RING_SIZE` resizes the ring. Attribution path
`usbdev_ioctl` → `file->private_data` → `usb_dev_state` → `usb_device` is stable across 6.8
and 6.17, and `usb_submit_urb` is exported. 32-bit needs no second probe: usbfs sets
`.compat_ioctl = compat_ptr_ioctl`, which funnels back into `usbdev_ioctl`. BPF has no
CLOCK_REALTIME helper. USB tracepoints carry no payload and are controller-specific — not
usable. `dummy_hcd` + `raw-gadget` works without hardware, minus isochronous. BTF is a hard
prerequisite, which together with `CLONE_INTO_CGROUP` sets the floor at Linux 5.7. Root for
all of v0.x.

**NOTE — `id == urb pointer` is a spike prerequisite, not a public guarantee**
It reflects current kernel internals (`ep->id = (unsigned long) urb`). If the main experiment
fails, or if that representation ever changes, fall back to `(bus, dev)` + time correlation.
The fallback is weaker but the rest of the design survives it unchanged.

---

## v0.1 — Attributed timeline

- Spawn the child directly inside a cgroup v2 via `clone3(CLONE_INTO_CGROUP)`; filter eBPF
  events by cgroup id. Startup order: create cgroup → attach BPF → open usbmon → clone3 → exec.
- Track `sched_process_exec` and `sched_process_exit`.
- eBPF per-TID flag: set on `usbdev_ioctl` entry, cleared on return. On `usb_submit_urb`, if
  the flag is set, emit `{urb_ptr, pid, tid, ts}`.
- Join usbmon `id` to `urb_ptr`. Exact match — no time windows, no ambiguity when two
  processes share a device.
- Label every URB without a match `[unattributed]`.
- Retention: keep exact matches; keep unmatched URBs on devices the session claimed; drop
  everything else before it reaches disk.
- Read `/dev/usbmon0` — all buses, since a traced command may touch several devices and we
  don't want to know which in advance.
- Normalise clocks: usbmon is CLOCK_REALTIME, BPF is CLOCK_MONOTONIC. Sample the offset
  periodically, flag REALTIME steps.
- Pair submit and completion on `(id, submit_ts)`; evict entries that never complete.
- Enlarge the usbmon ring via `MON_IOCT_RING_SIZE`, poll `MON_IOCG_STATS`, report drops loudly.
- Show `len_urb` vs `len_cap`; mark `[TRUNCATED]` when they differ.
- Put state-changing ioctls on the timeline: `RESET`, `CLEAR_HALT`, `SETINTERFACE`,
  `DISCARDURB`.
- Resolve VID:PID and product strings from sysfs.
- Control, bulk and interrupt transfers. Plain text timeline on stdout.

```
0.012  st-flash(4473)   open   001/004 [0483:3748 ST-LINK]
0.014  st-flash(4473)   CTRL   OUT  len=16
1.204  st-flash(4473)   BULK   OUT  ep=0x02 len=1024
2.007  [unattributed]   INTR   IN   ep=0x81 len=8   (001/004, session device)
```

Not in this version: hotplug, pcapng, aggregation, payload decoding, isochronous transfers.

**Done:** run against `st-flash` / `dfu-util` / `esptool`; every transfer either attributed to
the right process or explicitly marked `[unattributed]`; verified by hand against Wireshark.

**NOTE — why `[unattributed]` and not `[kernel]`**
A missing match proves only that no usbfs attribution event was seen. The URB could come from
a kernel driver, another process, or an async resubmit. Claiming kernel origin would be
inventing an attribution — the one thing this tool must never do.

**NOTE — why unmatched URBs on session devices are kept**
Composite devices expose several interfaces at once. ST-Link is one: a usbfs debug interface
plus a CDC-ACM serial interface driven by a kernel driver. Keeping only exact matches would
silently discard half the traffic of your own debug probe, and "the target's printf output
stopped" becomes undebuggable in the very tool meant to debug it. Dropping URBs from devices
the session never claimed is what keeps keyboards and webcams out of the capture.

**NOTE — clock error cannot corrupt attribution**
The join is on `urb_ptr`, not on time. A bad clock offset skews the displayed timeline and
nothing else. Don't budget risk for it as if it were a correctness issue.

---

## v0.2 — Hotplug and re-enumeration

- Listen on the netlink uevent socket directly, not udev.
- Read port topology from sysfs; key everything on physical port path (`1-1.4`).
- Record VID:PID, bus/address, port path, product strings per event.
- Extend the session's device claim across re-enumeration via port path, so retention keeps
  working when the device returns with a new address and VID:PID.
- Mark `probable re-enumeration` when a session device disappears and another appears on the
  same port within ~2s. Show the evidence; report as probable, not fact.
- Add a reorder buffer — uevent and usbmon streams arrive with different latencies.

```
3.881                    USB REMOVE 001/004 [0483:3748]  port 1-1.4
4.402                    USB ADD    001/007 [0483:df11]  port 1-1.4
                           ↳ probable re-enumeration (same port, +521ms)
```

**Done:** a flash script that drops a device into DFU and back produces one unbroken timeline.

**NOTE — why netlink and not udev**
udevd sits in userspace and adds tens to hundreds of milliseconds of latency. That delay lands
exactly on the transition this version exists to capture. Bus addresses are also reused and
reassigned on reconnect, which is why correlation keys on port path instead.

---

## v0.3 — pcapng export

- `usbtrail --pcap out.pcapng -- <command>`
- Write `LINKTYPE_USB_LINUX_MMAPPED` (220) with the 64-byte Linux USB pseudo-header.
- Capture is pre-filtered to the traced session.
- Attach process metadata per packet if the format allows, otherwise emit a sidecar JSON map.

**Done:** a capture spanning re-enumeration opens in Wireshark with correct dissection.

**NOTE — this deletes a whole backlog**
HID, SCSI, DFU, descriptor and mass-storage decoding all become Wireshark's problem
permanently. Worth doing early for that reason alone.

---

## v0.4 — Output UX

- Run-length aggregation: `BULK OUT ep=0x02 len=1024 ×248  (1.20s–3.88s, 203 KiB)`
- `--verbose` / `--raw` to disable aggregation.
- Filters by process, device, transfer type, endpoint.
- `--json` structured output.
- Summary footer: per-process and per-device totals, bytes, duration, errors, dropped events.

**Done:** a full firmware flash fits on one screen.

---

## v0.5 — Hardening

- Bounded BPF maps with time-based eviction; verify behaviour under map pressure.
- Confirm `USBDEVFS_BULK` and `USBDEVFS_CONTROL` are covered by the `usb_submit_urb` probe.
- Capability-only operation instead of root, tested on real distro kernels.
- Behaviour when a device is yanked mid-transfer, and under ring-buffer saturation.
- Regression tests on `dummy_hcd` / `raw-gadget` in CI.

**Done:** the full CI suite runs with no hardware; traces comparable across runs.

**NOTE — possible clock refinement**
If sampled-offset drift turns out to be visible in practice, `bpf_ktime_get_tai_ns()` (6.1+)
plus the TAI−UTC offset is an alternative. Only worth it if the problem is real.

---

## v1.0

- CLI surface stable, JSON schema versioned.
- Attribution semantics specified, including what `[unattributed]` does and does not claim.
- Limitations documented in README.
- Works on two distros and three kernel versions.
- You've used it to solve a real bug you couldn't have solved otherwise.

---

## Known limitations — put these in the README

- Kernel-driver traffic is never attributed. `/dev/ttyUSB0`, hidraw and similar appear as
  `[unattributed]` when the device is claimed by the session, and are dropped otherwise.
- `[unattributed]` is an absence of proof, not a claim of kernel origin.
- Payload may be truncated or absent — `len_cap` can be below `len_urb`, and some
  DMA/scatter-gather cases aren't captured at all.
- Isochronous transfers unsupported; `dummy_hcd` can't emulate them anyway.
- Root required in v0.x.
- Linux 5.7+ with kernel BTF only. Distributions shipping without `CONFIG_DEBUG_INFO_BTF` are
  unsupported by design — no fallback mode is planned.
- Reads all buses. Traffic from unclaimed devices is discarded in the correlator and never
  written to disk, by design.

## Out of scope

Protocol decoding (Wireshark's job). Wire-level capture (sigrok's job). CAN and I2C. Windows
and macOS. GUI before v1.0 — JSON is the integration point.
## Out of scope for v1.0

Protocol decoding (Wireshark's job). Wire-level capture (sigrok's job). CAN and I2C. Windows
and macOS. GUI before v1.0 — JSON is the integration point.
