# USBTrail — Roadmap

Process-oriented USB tracer for Linux.

```bash
usbtrail -- ./flash.sh
```

Follows one command and all its children, and shows what they did on USB — across device
re-enumeration. Filters by process, not by device address.

**Stack:** C++17 + libbpf/CO-RE. Spikes in Python + bcc/bpftrace.

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

- **usbmon binary API.** `id` is the URB pointer, carried from submit to callback.
  Timestamps come from `ktime_get_real_ts64` — **CLOCK_REALTIME**. `len_urb` is the real
  length, `len_cap` what was actually captured; they differ. `MON_IOCG_STATS` reports dropped
  events; `MON_IOCT_RING_SIZE` resizes the ring buffer.
- **Attribution.** `usbdev_ioctl` → `usbdev_do_ioctl` → `file->private_data` →
  `usb_dev_state` → `usb_device`. Stable across 6.8 and 6.17. `usb_submit_urb` is exported and
  runs in task context when called via usbfs.
- **USB tracepoints.** Generic ones carry device-level events only; xHCI ones carry URB
  metadata but no payload, and are controller-specific. Not needed.
- **Test rig.** `dummy_hcd` + `/dev/raw-gadget` works without hardware. No isochronous support.
- **BTF.** Required prerequisite; hard-fail if `/sys/kernel/btf/vmlinux` is absent.
- **Privileges.** Root for v0.1. Capability-only mode is a later question.

### Open — verify on two kernels

1. **The main experiment.** A probe on `usbdev_ioctl` → `usb_submit_urb` yields a URB pointer
   that matches `id` in the usbmon stream. If this holds, exact attribution is confirmed and
   the whole architecture stands. If not, fall back to `(bus, dev)` + time correlation.
2. **Clock offset strategy.** usbmon is CLOCK_REALTIME, `bpf_ktime_get_ns()` is
   CLOCK_MONOTONIC. Decide: `bpf_ktime_get_real_ns()` where available, or a sampled offset —
   and how to handle NTP stepping mid-trace.
3. **`usbdev_compat_ioctl`** — present, and reachable by the same probe pattern?
4. **fentry vs kprobe.** `usbdev_ioctl` is static; check whether fentry attaches or a kprobe
   is required.

### Smoke test

```bash
uname -r
sudo modprobe usbmon && ls -l /dev/usbmon*
test -r /sys/kernel/btf/vmlinux
grep -c usb_submit_urb /proc/kallsyms
grep -c usbdev_compat_ioctl /proc/kallsyms
bpftool btf dump file /sys/kernel/btf/vmlinux format c | grep -c usb_dev_state
sudo modprobe dummy_hcd raw_gadget && ls -l /dev/raw-gadget
clang --version
```

**Done:** the main experiment reproduces on two kernels.

---

## v0.1 — Attributed timeline

### Attribution — the core mechanism

- eBPF, per-TID flag:
  - `usbdev_ioctl` / `usbdev_compat_ioctl` entry → `active_usbfs[tid] = {bus, dev}`
  - `usb_submit_urb` → if the flag is set, emit `{urb_ptr, pid, tid, ts}`
  - ioctl return → clear the flag
- Join on `usbmon.id == urb_ptr`. Exact — no time windows, no ambiguity between two processes
  sharing a device.
- No flag set → `[kernel]`. **Never invent an attribution.**

### Rest of scope

- `usbtrail -- <command>`: spawn, trace command and all descendants.
- Session isolation via cgroup v2; filter eBPF events by cgroup id.
- Process events: `sched_process_exec`, `sched_process_exit`.
- Read `/dev/usbmon0` (all buses — a device can re-enumerate onto a different bus).
- **Clock normalisation** between CLOCK_REALTIME and CLOCK_MONOTONIC; re-sample the offset
  periodically and flag REALTIME steps.
- **Drop detection:** enlarge the ring via `MON_IOCT_RING_SIZE`, poll `MON_IOCG_STATS`, and
  report losses loudly in the output.
- **Truncation:** show `len_urb` vs `len_cap`, mark `[TRUNCATED]` when they differ.
- Submit/completion pairing keyed on `(id, submit_ts)` — the kernel recycles URB pointers.
  Evict entries that never complete.
- State-changing ioctls on the timeline too: `RESET`, `CLEAR_HALT`, `SETINTERFACE`,
  `DISCARDURB` — they produce no URB but cause half of all flashing bugs.
- Resolve VID:PID and product strings from sysfs.
- Control, bulk, interrupt transfers.
- **Discard non-session URBs in the correlator, before anything reaches disk.** The capture
  includes every bus, keyboards included.
- Plain text timeline on stdout.

```
0.012  st-flash(4473)   open   001/004 [0483:3748 ST-LINK]
0.014  st-flash(4473)   CTRL   OUT  len=16
1.204  st-flash(4473)   BULK   OUT  ep=0x02 len=1024
2.007  [kernel]         INTR   IN   ep=0x81 len=8
```

**Done:** run against `st-flash` / `dfu-util` / `esptool`; every transfer either attributed to
the right process or explicitly marked `[kernel]`; verified by hand against Wireshark.

---

## v0.2 — Hotplug and re-enumeration

- Listen on the **netlink uevent socket directly**, not udev — udevd adds tens to hundreds of
  milliseconds of latency, which matters precisely at the transition.
- Pull port topology from sysfs: **physical port path** (`1-1.4`), stable across
  re-enumeration. Never correlate on bus address.
- Record VID:PID, bus/address, port path, product strings.
- Mark `probable re-enumeration` when a session's device disappears and another appears on the
  same port within ~2s. Show the evidence; report as probable, not fact.
- Reorder buffer — uevent and usbmon streams arrive with different latencies.

```
3.881                    USB REMOVE 001/004 [0483:3748]  port 1-1.4
4.402                    USB ADD    001/007 [0483:df11]  port 1-1.4
                           ↳ probable re-enumeration (same port, +521ms)
```

**Done:** a flash script that drops a device into DFU and back produces one unbroken timeline.

---

## v0.3 — pcapng export

- `usbtrail --pcap out.pcapng -- <command>`
- Write usbmon-format records (Linux mmapped USB link type), readable by Wireshark.
- Capture is pre-filtered to the traced session — that's the point.
- Process metadata per packet if the format allows, otherwise a sidecar JSON map.

Removes HID, SCSI, DFU, descriptor and mass-storage decoding from the backlog permanently.

**Done:** a capture spanning re-enumeration opens in Wireshark with correct dissection.

---

## v0.4 — Output UX

- Run-length aggregation: `BULK OUT ep=0x02 len=1024 ×248  (1.20s–3.88s, 203 KiB)`
- `--verbose` / `--raw` to disable it.
- Filters by process, device, transfer type, endpoint.
- `--json` structured output.
- Summary footer: per-process and per-device totals, bytes, duration, errors, dropped events.

**Done:** a full firmware flash fits on one screen.

---

## v0.5 — Hardening

- Bounded BPF maps with time-based eviction; verify behaviour under map pressure.
- Synchronous usbfs paths: `USBDEVFS_BULK`, `USBDEVFS_CONTROL` — confirm they are covered by
  the `usb_submit_urb` probe, add handling if not.
- Capability-only operation instead of root, tested on real distro kernels.
- Behaviour when a device is yanked mid-transfer, and under ring-buffer saturation.
- Regression tests on `dummy_hcd` / `raw-gadget` in CI.

**Done:** full CI suite runs with no hardware; traces comparable across runs.

---

## v1.0

- CLI surface stable, JSON schema versioned.
- Attribution semantics specified, including when it reports `[kernel]`.
- Limitations documented in README.
- Works on two distros and three kernel versions.
- You've used it to solve a real bug you couldn't have solved otherwise.

---

## Known limitations

- **Kernel-driver devices degrade.** For `/dev/ttyUSB0`, hidraw and similar, the driver
  generates USB traffic asynchronously in another context. Those transfers show as `[kernel]`.
- **Payload may be truncated or absent** — `len_cap` can be less than `len_urb`, and some
  DMA/scatter-gather cases are not captured at all.
- **Isochronous transfers unsupported**, and `dummy_hcd` can't emulate them anyway.
- **Elevated privileges required** (root in v0.x).
- **Reads all buses.** Non-session traffic is discarded in the correlator and never written to
  disk, by design.

## Out of scope for v1.0

Protocol decoding (Wireshark's job). Wire-level capture (sigrok's job). CAN and I2C. Windows
and macOS. GUI before v1.0 — JSON is the integration point.
