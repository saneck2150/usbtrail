#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

required_tools=(clang-format ruff shfmt)

for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "error: required tool '$tool' is not available." >&2
        echo "Run this command inside the USBTrail dev container:" >&2
        echo "  docker compose run --rm dev ./scripts/format-check.sh" >&2
        exit 1
    fi
done

failed=0

echo "==> Checking C/C++/BPF formatting"

while IFS= read -r -d '' file; do
    if ! clang-format --dry-run --Werror "$file"; then
        failed=1
    fi
done < <(
    find src include bpf tests/cpp \
        -type f \
        \( \
        -name '*.c' \
        -o -name '*.h' \
        -o -name '*.cc' \
        -o -name '*.cpp' \
        -o -name '*.hpp' \
        \) \
        -print0
)

echo "==> Checking Python formatting"

if ! ruff format --check tests/python tools; then
    failed=1
fi

echo "==> Checking Bash formatting"

if ! shfmt \
    -d \
    -i 4 \
    -ci \
    scripts \
    docker/entrypoint.sh; then
    failed=1
fi

exit "$failed"
