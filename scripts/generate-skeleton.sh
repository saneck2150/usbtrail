#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "usage: $0 <bpftool> <bpf-object> <output-skeleton.h>" >&2
    exit 2
fi

bpftool="$1"
object="$2"
output="$3"
tmp="${output}.tmp"

mkdir -p "$(dirname "$output")"

"$bpftool" gen skeleton "$object" >"$tmp"
mv "$tmp" "$output"
