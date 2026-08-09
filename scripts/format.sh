#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

echo "==> Formatting C/C++/BPF"

find src include bpf tests/cpp \
    -type f \
    \( \
        -name '*.c' \
        -o -name '*.h' \
        -o -name '*.cc' \
        -o -name '*.cpp' \
        -o -name '*.hpp' \
    \) \
    -print0 |
    xargs -0 -r clang-format -i

echo "==> Formatting Python"

ruff format tests/python tools

echo "==> Formatting Bash"

shfmt \
    -w \
    -i 4 \
    -ci \
    scripts \
    docker/entrypoint.sh

echo "==> Done"