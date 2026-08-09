#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

required_tools=(ruff shellcheck)

for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "error: required tool '$tool' is not available." >&2
        echo "Run this command inside the USBTrail dev container:" >&2
        echo "  docker compose run --rm dev ./scripts/lint.sh" >&2
        exit 1
    fi
done

echo "==> Ruff"
ruff check tests/python tools

echo "==> ShellCheck"
shellcheck scripts/*.sh docker/*.sh

echo "==> Done"
