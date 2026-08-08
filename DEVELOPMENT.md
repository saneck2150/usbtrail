# USBTrail — Development Roadmap

**Process-oriented USB tracer for Linux.**

> Not a USB analyzer. A causal debugger for commands that talk to USB devices.

`usbmon` and Wireshark are `tcpdump` for USB: they sit on the wire and show everything.
USBTrail is `strace` for USB: it follows one command and shows what *that command and its
children* did — across device re-enumeration.

```bash
usbtrail -- ./flash.sh
```

---

## Design principles

These should survive every version. If a feature violates one, it belongs in a different tool.

1. **Attribution is the product.** Anything that doesn't help answer "which process caused
   this?" is secondary.
2. **Never guess an attribution.** An honest `[unattributed]` is worth more than a plausible
   wrong PID. Silent misattribution destroys trust in a debugger.
3. **Don't rebuild what the kernel already gives you.** `usbmon` already produces complete URB
   records. The novel part is the PID join — build only that.
4. **Don't compete with Wireshark. Feed it.** Emit standard capture formats so protocol
   decoding stays someone else's problem.
5. **Correlate on physical port, never on bus address.** Bus addresses change on
   re-enumeration — which is exactly the moment the user cares about.
6. **Ship narrow.** Every version below has an explicit non-goals list. Respect it.

---

## Version overview

| Version | Theme | Ships to users? |
|---|---|---|
| v0.0.x | De-risking spikes | No — throwaway code |
| v0.1.0 | Attributed timeline (the core) | Yes — first useful release |
| v0.2.0 | Hotplug + re-enumeration | Yes — the differentiator |
| v0.3.0 | pcapng export | Yes |
| v0.4.0 | Output UX: aggregation, filters, JSON | Yes |
| v0.5.0 | Correctness hardening | Yes |
| v1.0.0 | Stable CLI + format contract | — |

---

## v0.0.x — Spikes

**Goal:** answer the unknowns that determine the architecture. Do not write product code yet.
Every hour spent here saves a week later.

Write these as disposable scripts (Python + `bcc`, or `bpftrace` one-liners). Delete them
afterwards. The deliverable is *answers*, not code.

### Open questions to close

**Q1 — Does the usbmon binary API give us everything?**
Read from `/dev/usbmon<N>`. Confirm you get: bus number, device number, endpoint, transfer
type, direction, submit/completion pairing, status, timestamps, and **full payload bytes**.
Check the text interface under `/sys/kernel/debug/usb/usbmon/` too — it's far easier to parse
but truncates data, so it may be fine for a spike and wrong for the product.

**Q2 — Can we get `PID ↔ (busnum, devnum)` reliably?**
Two candidate approaches — pick one by experiment:
- *Track opens:* probe `openat` on paths matching `/dev/bus/usb/*`, plus `close`, and maintain
  an fd table. Simple, but fd tables are annoying (dup, fork, exec, CLOEXEC).
- *Probe usbfs directly:* kprobe `usbdev_ioctl`, read `file->private_data` →
  `struct usb_dev_state` → `struct usb_device` → `busnum`/`devnum`. Gives the mapping at every
  submission with no fd bookkeeping. Needs CO-RE and testing across kernel versions.

The second is cleaner if it works. Verify on at least two kernel versions.

**Q3 — Can we detect *invalid* attribution?**
`usb_submit_urb` also runs from workqueues, driver kthreads, and completion handlers that
resubmit. In those contexts `bpf_get_current_pid_tgid()` returns *something* — and it is wrong.
Find a reliable signal for "this transfer originated from usbfs in task context." Without it,
principle #2 is unenforceable.

**Q4 — Are there stable USB tracepoints, and what do they carry?**
If you end up needing eBPF on URBs directly, check whether your kernels expose usb tracepoints
and whether they include payload or only metadata. Suspicion: metadata only. Confirm before
designing around them.

**Q5 — Does `dummy_hcd` give us a test rig?**
`modprobe dummy_hcd` provides a virtual host controller. Combined with configfs gadgets — or
`/dev/raw-gadget`, which lets userspace synthesize arbitrary USB devices — this should allow
reproducible tests and CI with no hardware plugged in. Confirm early; it changes how testable
the whole project is.

**Q6 — Privileges.** Determine the minimum capability set. Full root, or is
`CAP_BPF` + `CAP_PERFMON` + read access to `/dev/usbmon*` enough? Document the answer.

### Done when
You can state, in writing, the answer to Q1–Q6 and have chosen the attribution mechanism.

---

## v0.1.0 — Attributed timeline

**Goal:** the smallest version *you* would actually run. One command in, one timeline out.

### Scope
- `usbtrail -- <command>` — spawn the command, trace it and all descendants.
- **Session isolation via cgroup v2:** create a cgroup, migrate the child into it, filter eBPF
  events by cgroup id. More robust than reconstructing fork trees, and handles daemonizing and
  re-parented processes for free.
- Process events: `exec` and `exit` (tracepoints `sched_process_exec` / `sched_process_exit`).
- usbmon reader: consume URB records from all buses.
- **The join:** `(busnum, devnum)` + timestamp → owning PID → session.
- Device identity: resolve `VID:PID` and product/manufacturer strings from sysfs on first sight.
- Transfer types: control, bulk, interrupt. (Isochronous can wait.)
- Submit/completion pairing with latency.
- Plain text timeline on stdout.

### Target output
```
0.000  flash.sh(4471)   start
0.011  st-flash(4473)   exec
0.012  st-flash(4473)   open   001/004 [0483:3748 ST-LINK]
0.014  st-flash(4473)   CTRL   OUT  len=16
0.019  st-flash(4473)   BULK   IN   ep=0x81 len=64
1.204  st-flash(4473)   BULK   OUT  ep=0x02 len=1024
```

### Non-goals for this version
No hotplug handling. No pcapng. No aggregation of repeated lines. No payload decoding. No
attribution through kernel drivers (`/dev/ttyUSB0`). No GUI. Linux only.

### Done when
You run it against a real flashing tool (`st-flash`, `dfu-util`, `esptool`) and every transfer
is attributed to the correct process, verified by hand against Wireshark output.

### Risks
The join is `(busnum, devnum)`-scoped, not per-URB. Two processes holding the same device open
simultaneously cannot be told apart. Rare in flashing workflows — accept it, document it,
revisit only if someone complains.

---

## v0.2.x — Hotplug and re-enumeration

**Goal:** the feature nothing else has. This is what the README demo is built around.

### Scope
- Subscribe to udev for USB `add` / `remove` events.
- Record for each event: `VID:PID`, bus/address, **physical port path** (e.g. `1-1.4`, stable
  across re-enumeration), product/manufacturer.
- Insert device lifecycle events into the timeline.
- **Re-enumeration heuristic.** Mark `probable re-enumeration` when all of the following hold:
  1. a device in use by this session disappeared;
  2. a device appeared on the *same physical port* within a time window (start ~2s, tunable);
  3. optionally reinforced by a process in the same session subsequently opening it.

  Report it as *probable*, with the evidence shown. Never assert it as fact.

### Target output
```
3.881                    USB REMOVE 001/004 [0483:3748]  port 1-1.4
4.402                    USB ADD    001/007 [0483:df11]  port 1-1.4
                           ↳ probable re-enumeration (same port, +521ms)
4.405  dfu-util(4491)  exec
4.410  dfu-util(4491)  open   001/007 [0483:df11 STM32 DFU]
```

### Done when
A full `flash.sh` that drops a device into DFU and back produces one unbroken timeline.

### Risks
udev events and usbmon records arrive on different paths with different latencies; ordering
near the transition needs care. Consider a small reorder buffer keyed on kernel timestamps.

---

## v0.3.x — pcapng export

**Goal:** stop owning the protocol-decoding problem forever.

### Scope
- `usbtrail --pcap out.pcapng -- <command>`
- Write usbmon-format records (Linux mmapped USB link type) so Wireshark opens them natively.
- The capture is **pre-filtered to the traced session** — that is the whole value proposition:
  a Wireshark capture containing only your command's traffic.
- Attach PID/process name as per-packet metadata if the format allows; otherwise emit a
  sidecar JSON mapping and document it.

### Why this early
It is cheap, and it deletes an entire category from the backlog: HID parsing, SCSI, DFU,
descriptor decoding, mass storage — all of it becomes Wireshark's job. Every hour here saves
many later.

> **Ordering note:** v0.2 and v0.3 can swap. v0.2 makes the project *distinctive*; v0.3 makes
> it *practically useful sooner*. If early users care more about real debugging than about the
> demo, do pcapng first.

### Done when
A capture from a re-enumerating device opens cleanly in Wireshark with correct dissection.

---

## v0.4.x — Output UX

**Goal:** make long traces readable. A 248-line bulk transfer loop is currently unusable.

### Scope
- Run-length aggregation of identical consecutive transfers:
  `BULK OUT ep=0x02 len=1024 ×248  (1.20s–3.88s, 203 KiB)`
- `--verbose` / `--raw` to disable aggregation.
- Filters: by process, by device, by transfer type, by endpoint.
- `--json` structured output for scripting and for future frontends.
- Summary footer: per-process and per-device totals, bytes, duration, error counts.

### Done when
A full firmware flash fits on one screen without losing anything important.

---

## v0.5.x — Correctness hardening

**Goal:** make it trustworthy enough to believe when it disagrees with you.

### Scope
- **Unattributed marking.** Apply the Q3 result: transfers from kernel context are labelled
  `[kernel]`, never given a bogus PID.
- **URB pointer reuse.** If you key submit↔completion on the URB pointer, note that the kernel
  recycles freed pointers from the slab allocator almost immediately. Key on
  `(pointer, submit_timestamp)` and delete the entry on completion.
- **Leaked entries.** URBs that never complete (device yanked mid-transfer) otherwise live
  forever in the BPF map. Add time-based eviction with a bounded map size.
- **Event loss.** usbmon and BPF ring buffers drop under load. Detect drops and report them
  loudly in the output — a silently incomplete trace is a lie.
- Regression tests on `dummy_hcd` / `raw-gadget` in CI.

### Done when
CI runs the full suite with no hardware, and traces are byte-comparable across runs.

---

## Toward v1.0.0

v1.0 is not "more features." It is a promise. Declare 1.0 when:

- the CLI surface is stable and you're willing to keep it,
- the JSON schema is versioned and documented,
- attribution semantics are specified — including exactly when it says "I don't know",
- known limitations are written down honestly in the README,
- it works on at least two distros and three kernel versions,
- you have used it yourself to solve a real bug you couldn't have solved otherwise.

That last one matters more than the rest.

---

# Plan for v1.0.0 version
*Reuse usbmon (for v1.0 version)

                 devtrace -- ./flash.sh
                          │
                 Trace Session #42
                          │
            ┌─────────────┼──────────────┐
            │             │              │
            ▼             ▼              ▼
         usbmon          eBPF           udev
            │             │              │
        USB URB      process/device     add/remove
       + payload      attribution       + sysfs path
            │             │              │
            └─────────────┼──────────────┘
                          ▼
                      Correlator
                          │
                 filter + join + sort
                          │
                ┌─────────┴─────────┐
                ▼                   ▼
             CLI timeline       capture file  

---

## Permanent non-goals

State these in the README so nobody asks:

- **Not a protocol analyzer.** Decoding is Wireshark's job (see v0.3).
- **Not a wire-level tool.** No logic analyzer, no electrical layer — that's sigrok's job.
- **Not cross-bus in v0.x.** CAN and I2C may come later via the same syscall+PID mechanism, but
  scope creep here will kill the project.
- **No Windows/macOS.** The whole design rests on usbmon and eBPF.
- **No GUI before v1.0.** JSON output is the integration point; someone else can build a UI.
