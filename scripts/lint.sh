#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

echo "==> Ruff"
ruff check tests/python tools

echo "==> ShellCheck"
shellcheck scripts/*.sh docker/*.sh

echo "==> Done"