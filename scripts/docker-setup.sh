#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

cat > .env <<EOF
LOCAL_UID=$(id -u)
LOCAL_GID=$(id -g)
EOF

echo "Generated .env:"
cat .env
echo

docker compose build dev

echo
echo "USBTrail dev image built."
echo "Open it with:"
echo "  docker compose run --rm dev"
