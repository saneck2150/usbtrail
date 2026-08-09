#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 <bpftool> <output-vmlinux.h>" >&2
    exit 2
fi

bpftool="$1"
output="$2"
tmp="${output}.tmp"

if [[ ! -r /sys/kernel/btf/vmlinux ]]; then
    echo "error: /sys/kernel/btf/vmlinux is not readable" >&2
    exit 1
fi

mkdir -p "$(dirname "$output")"

"$bpftool" btf dump file /sys/kernel/btf/vmlinux format c >"$tmp"
mv "$tmp" "$output"
