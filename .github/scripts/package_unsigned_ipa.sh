#!/usr/bin/env bash

set -euo pipefail

app_path="${1:-build/ios/iphoneos/Runner.app}"
output_path="${2:-build/release/itouMD-unsigned.ipa}"

if [[ ! -d "$app_path" ]]; then
  echo "Missing iOS app bundle: $app_path" >&2
  exit 1
fi

if [[ "$output_path" != *.ipa ]]; then
  echo "Output path must end in .ipa: $output_path" >&2
  exit 1
fi

if find "$app_path" -name embedded.mobileprovision -print -quit | grep -q .; then
  echo "Refusing to package an app containing a provisioning profile." >&2
  exit 1
fi

if codesign --verify "$app_path" >/dev/null 2>&1; then
  echo "Refusing to package a signed app. Build with --no-codesign first." >&2
  exit 1
fi

mkdir -p "$(dirname "$output_path")"
output_dir="$(cd "$(dirname "$output_path")" && pwd)"
output_file="$output_dir/$(basename "$output_path")"
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/itoumd-ipa.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
archive_path="$staging_dir/archive.ipa"

mkdir -p "$staging_dir/Payload"
ditto "$app_path" "$staging_dir/Payload/Runner.app"
ditto -c -k --keepParent "$staging_dir/Payload" "$archive_path"
mv -f "$archive_path" "$output_file"

echo "Created unsigned IPA: $output_file"
