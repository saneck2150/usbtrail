#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

python3 -m venv .venv
. .venv/bin/activate

python -m pip install --upgrade pip
python -m pip install -r tools/requirements-dev.txt

echo "Host venv created at $repo_root/.venv"
echo "Activate with: source .venv/bin/activate"
