#!/bin/zsh
# Package an existing Schiera.app in a compressed DMG without downloading tools.
set -euo pipefail

usage() {
  print -u2 "Usage: scripts/package-dmg.sh APP_PATH OUTPUT_DMG [VOLUME_NAME]"
  exit 2
}

(( $# == 2 || $# == 3 )) || usage

APP_PATH="${1:A}"
OUTPUT_DMG="${2:A}"
VOLUME_NAME="${3:-Schiera}"

[[ -d "$APP_PATH" && "$APP_PATH" == *.app ]] || {
  print -u2 "App bundle not found: $APP_PATH"
  exit 1
}
[[ "$OUTPUT_DMG" == *.dmg && "$OUTPUT_DMG" != / ]] || {
  print -u2 "Output must be a specific .dmg path"
  exit 1
}
[[ -n "$VOLUME_NAME" ]] || {
  print -u2 "Volume name must not be empty"
  exit 1
}

STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/schiera-dmg.XXXXXX")"
[[ -d "$STAGING_ROOT" && "$STAGING_ROOT" != / ]] || {
  print -u2 "Could not create a safe staging directory"
  exit 1
}

cleanup() {
  if [[ -n "${STAGING_ROOT:-}" && -d "$STAGING_ROOT" && "$STAGING_ROOT" != / ]]; then
    rm -rf -- "$STAGING_ROOT"
  fi
}
trap cleanup EXIT INT TERM

mkdir -p "${OUTPUT_DMG:h}"
ditto "$APP_PATH" "$STAGING_ROOT/${APP_PATH:t}"
ln -s /Applications "$STAGING_ROOT/Applications"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_ROOT" \
  -format UDZO \
  -ov \
  "$OUTPUT_DMG"

hdiutil verify "$OUTPUT_DMG"
print "Created $OUTPUT_DMG"
