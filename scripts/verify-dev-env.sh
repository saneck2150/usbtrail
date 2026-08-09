#!/usr/bin/env bash
set -euo pipefail

required_tools=(
    cmake
    ninja
    clang
    clang-format
    bpftool
    bpftrace
    python
    pytest
    ruff
    shfmt
    shellcheck
)

failed=0

for tool in "${required_tools[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
        printf 'OK   %-16s %s\n' "$tool" "$(command -v "$tool")"
    else
        printf 'MISS %-16s\n' "$tool"
        failed=1
    fi
done

exit "$failed"
