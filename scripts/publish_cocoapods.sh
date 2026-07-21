#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
PROJECT_NAME="${2:-}"
PODSPEC_PATH="${3:-${PROJECT_NAME}.podspec}"

if [[ -z "$VERSION" || -z "$PROJECT_NAME" ]]; then
    echo "Usage: publish_cocoapods.sh <version> <project_name> [podspec_path]" >&2
    exit 1
fi
: "${COCOAPODS_TRUNK_TOKEN:?COCOAPODS_TRUNK_TOKEN is required}"
command -v pod >/dev/null || {
    echo "CocoaPods is required." >&2
    exit 1
}
[[ -f "$PODSPEC_PATH" ]] || {
    echo "Podspec not found: $PODSPEC_PATH" >&2
    exit 1
}

INFO="$(pod trunk info "$PROJECT_NAME" 2>/dev/null || true)"
if grep -E -q "^[[:space:]]*-[[:space:]]+${VERSION}[[:space:]]+\\(" <<<"$INFO"; then
    echo "$PROJECT_NAME $VERSION is already published."
    exit 0
fi

echo "Publishing $PROJECT_NAME $VERSION to CocoaPods."
pod trunk push "$PODSPEC_PATH"
