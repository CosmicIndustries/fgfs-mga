#!/usr/bin/env bash
# Move an existing generated output directory aside instead of deleting it.
# Usage: preserve-generated-dir.sh PATH
set -Eeuo pipefail

if [[ $# -ne 1 || -z "$1" ]]; then
  printf 'Usage: %s PATH\n' "$0" >&2
  exit 64
fi

path=$1
if [[ ! -e "$path" && ! -L "$path" ]]; then
  exit 0
fi
if [[ -L "$path" ]]; then
  printf 'ERROR: refusing to replace generated directory symlink: %s\n' "$path" >&2
  exit 1
fi
if [[ ! -d "$path" ]]; then
  printf 'ERROR: expected a generated directory, found another file type: %s\n' "$path" >&2
  exit 1
fi

backup=$(mktemp -d "${path}.backup.XXXXXXXX")
if ! mv -T -- "$path" "$backup/original"; then
  rmdir -- "$backup" 2>/dev/null || true
  printf 'ERROR: could not preserve existing generated directory: %s\n' "$path" >&2
  exit 1
fi
printf 'Preserved previous generated directory: %s\n' "$backup/original"
