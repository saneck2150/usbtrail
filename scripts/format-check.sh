#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

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