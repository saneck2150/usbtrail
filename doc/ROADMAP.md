# USBTrail — Roadmap

Process-oriented USB tracer for Linux.

```bash
usbtrail -- ./flash.sh
```

USBTrail follows one command and its descendants and produces one USB timeline
for that process tree, including device re-enumeration.

The primary filter is the **process tree**, not the USB bus/device address.

## Stack

Production:

- **C++20** — userspace tracer;
- **C / eBPF** — process → URB attribution;
- **libbpf + CO-RE** — BPF loading/relocations.

Development/tooling:

- **Python 3** — tests, spikes, fixtures and analysis;
- **Bash** — small build/setup glue;
- **CMake + Ninja**;
- **Docker Compose**.

```text
command + descendants
        │
        │ process attribution
        ▼
 eBPF: usbdev_ioctl → usb_submit_urb
        │
        │ struct urb * (exact join key)
        ▼
    correlator ◄──── binary usbmon
        │       ◄──── netlink uevent + sysfs
        │              (hotplug, identity, topology)
        │
   ┌────┴────┐
   ▼         ▼
timeline   pcapng
```

---

# Support policy

The early implementation deliberately targets the modern BPF/BTF path first.

Current v0.x assumptions:

- Linux;
- kernel BTF is a hard prerequisite;
- required BPF trampoline/probe support must be available;
- root/privileged access is acceptable during v0.x development.

There is currently **no non-BTF fallback**.

The exact minimum supported kernel version is intentionally deferred until
v0.5. Old-kernel compatibility must not complicate v0.1 before the core tracer
works.

The initial runtime validation was performed on:

```text
Linux Mint
kernel 6.17.0-20-generic
x86_64
```

A second machine with Ubuntu 24.04 / kernel `7.0.0-28-generic` is available for
later portability testing, but a second-kernel rerun is **not a v0.0 completion
gate**.

---

# v0.0 — Core attribution spike ✅ DONE

Throwaway C + bpftrace experiments.

## Goal

Prove that USBTrail can obtain an exact process → kernel URB → usbmon join.

Required runtime chain:

```text
USBDEVFS_SUBMITURB
        │
        ▼
usbdev_ioctl ENTRY
        │
        ▼
usb_submit_urb
        │
        ▼
usbdev_ioctl RETURN
```

and:

```text
BPF struct urb * == usbmon id
```

## Verified results

- [x] usbmon available.
- [x] `/sys/kernel/btf/vmlinux` readable.
- [x] `usb_dev_state` present in BTF.
- [x] `usbdev_ioctl` present in BTF.
- [x] `usb_submit_urb` present in BTF.
- [x] fentry/trampoline-style attachment works for `usbdev_ioctl`
      (`kfunc` syntax in bpftrace 0.20.2).
- [x] fentry/trampoline-style attachment works for `usb_submit_urb`.
- [x] classic kprobe attachment is available as a fallback.
- [x] kretfunc attaches to `usbdev_ioctl`.
- [x] a controlled `USBDEVFS_SUBMITURB` request reaches `usbdev_ioctl`.
- [x] the request reaches `usb_submit_urb`.
- [x] `usb_submit_urb` executes inside the same `usbdev_ioctl` call window.
- [x] `ENTRY → SUBMIT → RETURN` was observed on the same TID.
- [x] `usbdev_ioctl` returned `0` for the successful submission.
- [x] `struct urb *` observed at `usb_submit_urb` exactly matched usbmon's ID.
- [x] the controlled USB transfer completed successfully.

Observed sandwich:

```text
ENTRY  pid=183511 tid=183511 cmd=0x8038550a
SUBMIT pid=183511 tid=183511 urb=0xffff8e92965e3cc0
RETURN pid=183511 tid=183511 ret=0
```

Observed exact join in the earlier correlation run:

```text
usb_submit_urb:
0xffff8e91cbed0780

usbmon:
 ffff8e91cbed0780
```

Therefore:

> **v0.0 DONE — core process-to-URB attribution feasibility is established for
> the selected BTF-enabled kernel path.**

The exact join key between process attribution and USB traffic is the kernel
`struct urb *` / usbmon ID on the validated path.

---

## v0.0 desk-research conclusions

No additional v0.0 spike is required for these points:

- usbmon carries one ID from submission to callback;
- on the currently targeted kernel implementation, that ID reflects the URB
  pointer;
- this pointer representation is an implementation detail, not a public ABI
  guarantee;
- if it changes, `(bus, dev) + time` remains a weaker fallback correlation
  strategy;
- `len_urb` vs `len_cap` exposes payload truncation;
- `MON_IOCG_STATS` reports drops;
- `MON_IOCT_RING_SIZE` resizes the binary usbmon ring;
- BPF has no ordinary CLOCK_REALTIME helper suitable for directly sharing
  usbmon's wall-clock timestamp domain;
- USB tracepoints are not suitable as the main capture source because they do
  not provide the required payload path and are controller-specific;
- `dummy_hcd + raw-gadget` can provide a hardware-independent non-isochronous
  integration setup;
- the intended device-attribution traversal is:

```text
usbdev_ioctl
    ↓
file->private_data
    ↓
usb_dev_state
    ↓
usb_device
```

Runtime implementation of that traversal belongs to v0.1.

---

# Development environment

Initial repository/environment setup is part of the transition from the spike
to production v0.1.

Target environment:

- one `usbtrail-dev:local` Docker image;
- normal `dev` Compose service;
- privileged `integration` Compose service;
- C++20/CMake/Ninja toolchain;
- clang/LLVM + libbpf + bpftool;
- Python `/opt/venv`;
- clang-format / Ruff / shfmt / ShellCheck.

Environment acceptance is tracked in `DEVELOPMENT.md`.

---

# v0.1 — Attributed timeline

Goal: replace throwaway spike scripts with the first coherent production tracer.

## Day 1 — binary usbmon reader

The first implementation task is the binary usbmon path.

Read `/dev/usbmon0` so the session does not need to know the target USB bus in
advance.

Implement:

- binary usbmon ring setup;
- `MON_IOCT_RING_SIZE`;
- binary record parsing;
- submit/completion records;
- usbmon `id`;
- bus/device/endpoint;
- transfer type/direction;
- status;
- `len_urb`;
- `len_cap`;
- captured bytes;
- `[TRUNCATED]` when `len_cap != len_urb`;
- `MON_IOCG_STATS`;
- loud reporting of dropped events.

Text usbmon was useful for v0.0 only. The product path starts with the binary
API.

## BPF attribution

Port the proven spike to libbpf/CO-RE:

```text
usbdev_ioctl ENTRY
        │
        │ mark relevant per-TID state
        ▼
usb_submit_urb
        │
        │ emit process identity + struct urb *
        ▼
usbdev_ioctl EXIT
        │
        └── clear per-TID state
```

Filter the BPF stream to the target process-tree scope.

Join:

```text
BPF event:
    urb_ptr
       │
       │ exact key
       ▼
usbmon event:
    id
```

Every URB without a valid process match is labelled:

```text
[unattributed]
```

never guessed.

## Process-tree containment

Solve process containment during implementation rather than as a prerequisite
spike.

Work includes:

- create the session cgroup;
- attach tracing before target execution;
- evaluate/use `clone3(CLONE_INTO_CGROUP)` for the modern launch path;
- exec the requested target;
- track descendants;
- track `sched_process_exec` / `sched_process_exit`;
- make startup ordering race-safe for the supported kernel set.

The `clone3` behavior is therefore a **v0.1 implementation concern**, not
remaining v0.0 work.

## Device attribution

Implement the runtime traversal:

```text
struct file *
    ↓
file->private_data
    ↓
struct usb_dev_state *
    ↓
struct usb_device *
```

Use it to obtain the USB device identity/topology associated with the process
side of the event.

This traversal was desk-researched before v0.1, but runtime implementation is
done here.

## Timeline

Produce a plain-text stream such as:

```text
0.012  st-flash(4473)   open   001/004 [0483:3748 ST-LINK]
0.014  st-flash(4473)   CTRL   OUT  len=16
1.204  st-flash(4473)   BULK   OUT  ep=0x02 len=1024
2.007  [unattributed]   INTR   IN   ep=0x81 len=8   (001/004, session device)
```

Additional v0.1 behavior:

- pair submit/completion records;
- evict submissions that never complete;
- retain exact process matches;
- retain unmatched URBs only for devices claimed by the session;
- discard unrelated device traffic before it reaches disk;
- put state-changing usbfs ioctls on the timeline where useful;
- resolve VID:PID and product strings from sysfs;
- support control, bulk and interrupt transfers;
- normalize timestamps for presentation only.

Clock normalization must not affect attribution correctness: the exact join is
on URB identity, not time.

## v0.1 done when

Run against representative tools such as:

```text
st-flash
dfu-util
esptool
```

and every retained transfer is either:

- correctly attributed to the process tree; or
- explicitly marked `[unattributed]`.

Not in v0.1:

- hotplug/re-enumeration stitching;
- pcapng;
- aggregation UX;
- payload protocol decoding;
- isochronous support.

---

# v0.2 — Hotplug and re-enumeration

- listen on the netlink uevent socket directly;
- read physical port topology from sysfs;
- record VID:PID, bus/address, physical port path and product strings;
- extend session device claims across reconnects using the physical port path;
- mark a new device as **probable re-enumeration** when the evidence supports
  it rather than claiming certainty;
- add a reorder buffer because usbmon and uevent streams have different
  delivery latencies.

Example:

```text
3.881  USB REMOVE 001/004 [0483:3748]  port 1-1.4
4.402  USB ADD    001/007 [0483:df11]  port 1-1.4
         ↳ probable re-enumeration (same port, +521ms)
```

**Done:** a firmware workflow that drops into DFU and returns produces one
unbroken timeline.

---

# v0.3 — pcapng export

Add:

```bash
usbtrail --pcap out.pcapng -- <command>
```

- write `LINKTYPE_USB_LINUX_MMAPPED` traffic usable by Wireshark;
- export only the traced session;
- preserve enough metadata to associate packets with process/session state;
- use a sidecar map if the packet format cannot carry all desired process
  metadata cleanly.

**Done:** a capture spanning re-enumeration opens in Wireshark with correct USB
dissection.

Protocol-specific USB decoding remains Wireshark's job.

---

# v0.4 — Output UX

- run-length aggregation;
- `--verbose` / `--raw`;
- process/device/transfer/endpoint filters;
- `--json`;
- summary footer with per-process/per-device totals, bytes, duration, errors
  and dropped events.

Target output:

```text
BULK OUT ep=0x02 len=1024 ×248  (1.20s–3.88s, 203 KiB)
```

**Done:** a complete firmware flash is readable without drowning the user in
individual URBs.

---

# v0.5 — Compatibility and hardening

Compatibility work is deliberately deferred until the modern core works.

## 32-bit usbfs compatibility

Runtime-test:

```text
32-bit userspace
    ↓
USBDEVFS_SUBMITURB32
    ↓
usbdev_ioctl
    ↓
usb_submit_urb
```

Desk research indicates that usbfs compat handling funnels through the same
`usbdev_ioctl` attribution path, so no second process-attribution probe is
expected.

This becomes a runtime compatibility test here, not a v0.0 gate.

## Kernel support baseline

Decide the actual supported kernel floor.

- test additional BTF-enabled kernels;
- validate required trampoline/probe behavior;
- decide whether support for kernels without the modern cgroup launch path is
  valuable;
- only add a pre-`clone3(CLONE_INTO_CGROUP)` launch fallback if it has enough
  practical value;
- kernels without the required BPF/BTF facilities remain unsupported unless
  there is a strong reason to broaden the design.

## Hardening

- bounded BPF maps and eviction behavior;
- behavior under BPF/map pressure;
- confirm legacy synchronous usbfs operations (`USBDEVFS_BULK`,
  `USBDEVFS_CONTROL`) are covered by the chosen attribution strategy;
- reduce `privileged: true` / root usage to the minimum capability/device set;
- handle device removal mid-transfer;
- handle usbmon ring saturation;
- regression tests with `dummy_hcd` / `raw-gadget`;
- CI without physical USB hardware where possible.

**Done:** compatibility/support policy is explicit and the integration suite is
repeatable.

---

# v1.0

- stable CLI;
- versioned JSON schema;
- documented attribution semantics;
- documented `[unattributed]` semantics;
- tested across multiple distros/kernels in the chosen support range;
- pcapng + timeline workflows stable;
- used successfully to diagnose a real USB problem.

---

# Known limitations

These must be documented clearly before v1.0.

- `[unattributed]` means **no proven process attribution**, not “kernel”.
- Traffic generated by kernel drivers may remain unattributed.
- Payload can be truncated or unavailable.
- Isochronous support is initially out of scope.
- Root/privileged operation is acceptable in v0.x.
- Kernels without the required BPF/BTF path are unsupported.
- USBTrail may read all buses internally, but unrelated devices are discarded
  by the correlator and not written to the session output.

---

# Out of scope for v1.0

- protocol decoding — Wireshark's job;
- wire-level capture — logic analyzer/sigrok territory;
- CAN/I2C;
- Windows/macOS;
- GUI before the core CLI/JSON interface is stable.