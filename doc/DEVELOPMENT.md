# USBTrail — Development Environment

USBTrail uses one reproducible Docker development image and two Compose services.

```text
usbtrail-dev:local
        │
        ├── dev
        │   └── normal build / test / formatting / BPF compilation
        │
        └── integration
            └── privileged BPF / usbmon / real USB runtime tests
```

The development stack is:

- **C++20** — production userspace core;
- **C / eBPF + libbpf/CO-RE** — kernel-side process → URB attribution;
- **Python 3** — tests, spikes, fixtures and developer tooling;
- **Bash** — small build/setup glue;
- **CMake + Ninja** — build system;
- **Docker Compose** — reproducible development/runtime environment.

---

## 1. Docker mental model

```text
docker/Dockerfile
        │
        │ docker compose build
        ▼
usbtrail-dev:local          ← image
        │
        │ docker compose run
        ▼
running container
```

The **Dockerfile** is the recipe.

The **image** is the built, reusable development environment.

A **container** is a running instance of that image.

Linux containers use the **host kernel**. That is important for USBTrail:
the compiler/toolchain lives inside the image, while BPF, BTF and usbmon refer
to the actual kernel running on the host.

---

## 2. Host prerequisites

The current v0.x development path assumes:

- Linux host;
- Docker Engine;
- Docker Compose plugin;
- readable kernel BTF;
- root/privileged access for runtime BPF + usbmon integration tests.

Check:

```bash
docker --version
docker compose version

test -r /sys/kernel/btf/vmlinux \
    && echo "BTF OK" \
    || echo "BTF MISSING"
```

The initial verified development kernel is:

```text
Linux Mint
6.17.0-20-generic
x86_64
```

The exact minimum supported kernel version is intentionally **not fixed yet**.
Compatibility policy is revisited in v0.5.

---

## 3. First-time Docker setup

From the repository root:

```bash
./scripts/docker-setup.sh
```

The script writes your host UID/GID to `.env` and builds:

```text
usbtrail-dev:local
```

Manual equivalent:

```bash
printf 'LOCAL_UID=%s\nLOCAL_GID=%s\n' "$(id -u)" "$(id -g)" > .env
docker compose build dev
```

The image runs the normal `dev` service using those numeric UID/GID values so
files created in the bind-mounted repository remain owned by the host user.

Check the image:

```bash
docker image ls usbtrail-dev
```

Rebuild after changes to `docker/Dockerfile` or Python requirements:

```bash
docker compose build dev
```

Clean rebuild:

```bash
docker compose build --no-cache dev
```

---

## 4. Python environment

Inside Docker, Python dependencies are installed at image-build time into:

```text
/opt/venv
```

The Dockerfile puts:

```text
/opt/venv/bin
```

at the front of `PATH`, so no activation command is needed.

Inside the container:

```bash
which python
python --version
pytest --version
ruff --version
```

Expected Python path:

```text
/opt/venv/bin/python
```

Development dependencies are declared in:

```text
tools/requirements-dev.txt
```

After editing that file:

```bash
docker compose build dev
```

### Optional host-side Python environment

Docker is the primary environment, but a local venv can be created with:

```bash
./scripts/bootstrap-host.sh
source .venv/bin/activate
```

`.venv/` is ignored by Git.

---

## 5. Open the normal development container

```bash
docker compose run --rm dev
```

Inside it, verify:

```bash
id
echo "$HOME"

which python
python --version

cmake --version
ninja --version

clang --version
clang-format --version

bpftool version
bpftrace --version

ruff --version
shfmt --version
shellcheck --version
./scripts/verify-dev-env.sh
```

`id` is the preferred ownership check. The normal container intentionally uses
numeric host UID/GID values and does not depend on a named `usbtrail` account
existing inside the Ubuntu base image.

---

## 6. CMake presets

Available presets:

```bash
cmake --list-presets
```

Current configure/build presets:

```text
debug
debug-no-bpf
release
```

Normal debug build:

```bash
cmake --preset debug
cmake --build --preset debug
```

or:

```bash
./scripts/build.sh
```

C++-only build:

```bash
./scripts/build.sh debug-no-bpf
```

Release build:

```bash
./scripts/build.sh release
```

Generated build trees live under:

```text
build/<preset>/
```

---

## 7. BPF / CO-RE build pipeline

With:

```text
USBTRAIL_BUILD_BPF=ON
```

CMake generates:

```text
host /sys/kernel/btf/vmlinux
          │
          ▼
       bpftool
          │
          ▼
build/debug/generated/bpf/vmlinux.h
          │
          ▼
        clang
    -target bpf
          │
          ▼
usbtrail_bpf.bpf.o
          │
          ▼
       bpftool
    gen skeleton
          │
          ▼
usbtrail_bpf.skel.h
```

Current files involved:

```text
bpf/usbtrail.bpf.c
cmake/Bpf.cmake
scripts/generate-vmlinux.sh
scripts/generate-skeleton.sh
```

The BPF program in the repository is currently only a build smoke probe.
The real v0.1 implementation will replace it with the v0.0-proven
`usbdev_ioctl ENTRY → usb_submit_urb → usbdev_ioctl RETURN` attribution path.

### Important BTF rebuild rule

`vmlinux.h` is generated from the **host kernel BTF**, so its generation should
depend on:

```text
/sys/kernel/btf/vmlinux
```

as well as `scripts/generate-vmlinux.sh`.

This prevents an old generated `vmlinux.h` from being silently reused after a
host kernel update.

---

## 8. Formatting and linting

USBTrail exposes one project-level interface while using the best formatter for
each language:

```text
C / C++20 / eBPF  → clang-format
Python            → Ruff
Bash              → shfmt + ShellCheck
```

Configuration:

```text
.clang-format
pyproject.toml
.editorconfig
```

### Apply formatting

```bash
./scripts/format.sh
```

### Check formatting without modifying files

```bash
./scripts/format-check.sh
```

### Run linters

```bash
./scripts/lint.sh
```

Equivalent CMake targets:

```bash
cmake --build --preset debug --target format
cmake --build --preset debug --target format-check
cmake --build --preset debug --target lint
```

### Bash coverage

Formatting/linting should include both:

```text
scripts/*.sh
docker/entrypoint.sh
```

so every shell script in the repository follows the same style.

---

## 9. Tests

C++ tests:

```bash
ctest --preset debug
```

Python tests:

```bash
pytest -q
```

Combined project command:

```bash
./scripts/test.sh
```

The current C++ smoke test verifies that the basic C++20/CMake/Ninja build path
works.

---

## 10. Run the userspace skeleton

After a debug build:

```bash
./build/debug/usbtrail
```

At this stage it is only the userspace project skeleton; the real binary usbmon
reader and BPF loader/correlator belong to v0.1.

---

## 11. Privileged integration environment

Real BPF loading, usbmon access and USB integration tests use:

```bash
docker compose run --rm integration
```

The integration service currently uses:

```yaml
user: root
privileged: true
pid: host
```

and mounts:

```text
/sys/kernel/btf
/sys/kernel/debug
/sys/fs/bpf
```

This is intentionally broad during v0.1 bring-up.

The everyday `dev` service should remain unprivileged.

Later, after the exact required access set is known, replace
`privileged: true` with the minimum capabilities/devices.

Load usbmon explicitly on the host when necessary:

```bash
sudo modprobe usbmon
```

Then inside `integration` check:

```bash
id
ls -l /sys/kernel/btf/vmlinux
ls -l /dev/usbmon* 2>/dev/null || true

bpftool version
bpftool feature probe kernel
```

---

## 12. Language responsibilities

### C++20

Production userspace:

- CLI;
- process supervisor;
- binary usbmon reader;
- BPF event consumer;
- URB correlator;
- USB topology/session state;
- timeline;
- pcapng writer.

### C / eBPF

Kernel-side attribution:

- `usbdev_ioctl` entry/exit state;
- `usb_submit_urb` process attribution;
- compact events delivered to userspace.

### Python

Development support:

- test harnesses;
- fixtures;
- generators;
- spikes;
- analysis utilities.

Python is not intended to carry the main production tracing path.

### Bash

Small glue only:

- bootstrap;
- build/test wrappers;
- BTF/skeleton generation;
- developer convenience commands.

Application logic should not migrate into Bash.

---

## 13. Normal daily workflow

On the host:

```bash
docker compose run --rm dev
```

Inside `dev`:

```bash
./scripts/format-check.sh
./scripts/lint.sh
./scripts/build.sh
./scripts/test.sh
```

Apply formatting when needed:

```bash
./scripts/format.sh
```

For real BPF/USB runtime work:

```bash
exit
sudo modprobe usbmon
docker compose run --rm integration
```