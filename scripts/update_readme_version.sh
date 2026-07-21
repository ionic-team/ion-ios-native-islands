#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
LIB_NAME="${2:-}"
README_FILE="${3:-README.md}"

if [[ -z "$VERSION" || -z "$LIB_NAME" ]]; then
    echo "Usage: update_readme_version.sh <version> <lib_name> [readme_path]" >&2
    exit 1
fi
[[ -f "$README_FILE" ]] || {
    echo "README not found: $README_FILE" >&2
    exit 1
}

TEMP_FILE="$(mktemp)"
trap 'rm -f "$TEMP_FILE"' EXIT
sed -E \
    "s/(pod '$LIB_NAME', '~> )[0-9]+\\.[0-9]+(\\.[0-9]+)?'/\\1$VERSION'/g" \
    "$README_FILE" >"$TEMP_FILE"

grep -F -q "pod '$LIB_NAME', '~> $VERSION'" "$TEMP_FILE" || {
    echo "No CocoaPods version entry found for $LIB_NAME in $README_FILE." >&2
    exit 1
}
cp "$TEMP_FILE" "$README_FILE"
echo "Updated $README_FILE to $LIB_NAME $VERSION."
