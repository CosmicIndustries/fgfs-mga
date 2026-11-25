#!/usr/bin/env bash
# Verify a file against an independently supplied SHA-256 digest.
set -u

if [[ $# -ne 2 ]]; then
  printf 'Usage: %s EXPECTED_SHA256 FILE\n' "$0" >&2
  exit 64
fi

expected=$1
file=$2
if [[ ! "$expected" =~ ^[[:xdigit:]]{64}$ ]]; then
  printf 'ERROR: expected SHA-256 must be exactly 64 hexadecimal characters\n' >&2
  exit 64
fi
if [[ ! -f "$file" || -L "$file" ]]; then
  printf 'ERROR: not a regular, non-symlink file: %s\n' "$file" >&2
  exit 66
fi

if printf '%s  %s\n' "$expected" "$file" | sha256sum --check --status; then
  printf 'SHA-256 verified: %s\n' "$file"
else
  printf 'ERROR: SHA-256 mismatch: %s\n' "$file" >&2
  exit 1
fi
