#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

required_tools=(clang-format ruff shfmt)

for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "error: required tool '$tool' is not available." >&2
        echo "Run this command inside the USBTrail dev container:" >&2
        echo "  docker compose run --rm dev ./scripts/format.sh" >&2
        exit 1
    fi
done

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

echo "==> Sorting Python imports"
ruff check --fix --select I tests/python tools

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
