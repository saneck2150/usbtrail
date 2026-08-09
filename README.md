# USBTrail

Process-oriented USB tracer for Linux.

USBTrail runs a command and produces one timeline of what that command and its
descendants actually did with USB devices, including across device
re-enumeration.

usbmon and Wireshark are effectively bus-oriented USB capture tools. USBTrail's
goal is different:

> **follow a process tree first, then show its USB activity.**

```bash
usbtrail -- ./flash.sh
```

Example target output:

```text
0.012 st-flash(4473) open 001/004 [0483:3748 ST-LINK]
0.014 st-flash(4473) CTRL OUT len=16
1.204 st-flash(4473) BULK OUT ep=0x02 len=1024 ×248 (1.20s–3.88s, 203 KiB)
2.007 [unattributed] INTR IN ep=0x81 len=8 (001/004, session device)

3.881 USB REMOVE 001/004 [0483:3748] port 1-1.4
4.402 USB ADD 001/007 [0483:df11 STM32 BOOTLOADER] port 1-1.4
      ↳ probable re-enumeration (same port, +521ms)

4.410 dfu-util(4491) open 001/007
```

## Development

The project uses one Docker development image with separate normal and
privileged integration services.

Quick start:

```bash
./scripts/docker-setup.sh
docker compose run --rm dev
```

Then inside the development container:

```bash
./scripts/format-check.sh
./scripts/lint.sh
./scripts/build.sh
./scripts/test.sh
```

For BPF/usbmon runtime integration:

```bash
sudo modprobe usbmon
docker compose run --rm integration
```

Full setup and current environment acceptance checklist:

[DEVELOPMENT.md](DEVELOPMENT.md)

## Stack

Production:

- C++20;
- C / eBPF;
- libbpf / CO-RE;
- CMake + Ninja.

Development:

- Docker Compose;
- Python 3;
- Bash;
- clang-format;
- Ruff;
- shfmt;
- ShellCheck.

## Scope

Linux USB tracing for one command + descendants, with:

- exact process attribution where provable;
- explicit `[unattributed]` events otherwise;
- hotplug/re-enumeration tracking;
- pcapng export for Wireshark.

Protocol decoding itself remains out of scope.