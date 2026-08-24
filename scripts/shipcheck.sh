#!/usr/bin/env bash
set -u -o pipefail

ARTIFACT="${SHIPCHECK_ARTIFACT:-}"
EXPECTED_BUNDLE_ID="${SHIPCHECK_EXPECTED_BUNDLE_ID:-}"
EXPECTED_VERSION="${SHIPCHECK_EXPECTED_VERSION:-}"
EXPECTED_BUILD="${SHIPCHECK_EXPECTED_BUILD:-}"
EXPECTED_TEAM_ID="${SHIPCHECK_EXPECTED_TEAM_ID:-}"
EXPECTED_ARCHITECTURES="${SHIPCHECK_EXPECTED_ARCHITECTURES:-}"
REQUIRE_GATEKEEPER="${SHIPCHECK_REQUIRE_GATEKEEPER:-true}"
REQUIRE_NOTARIZATION="${SHIPCHECK_REQUIRE_NOTARIZATION:-true}"
LAUNCH_SMOKE="${SHIPCHECK_LAUNCH_SMOKE:-false}"
RECEIPT_PATH="${SHIPCHECK_RECEIPT_PATH:-shipcheck-receipt.json}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/shipcheck.XXXXXX")"
CHECKS_FILE="$TMP_DIR/checks.tsv"
: > "$CHECKS_FILE"
MOUNT_POINT=""
FAILURES=0

ARTIFACT_TYPE="unknown"
APP_PATH=""
BUNDLE_ID=""
VERSION=""
BUILD=""
TEAM_ID=""
ARCHITECTURES=""
SHA256=""
ENTITLEMENTS_SHA256=""

cleanup() {
  if [[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]]; then
    hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

is_true() {
  case "${1,,}" in
    true|1|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

sanitize() {
  printf '%s' "$1" | tr '\t\r\n' '   '
}

record() {
  local name="$1" status="$2" detail="$(sanitize "${3:-}")"
  printf '%s\t%s\t%s\n' "$name" "$status" "$detail" >> "$CHECKS_FILE"
  if [[ "$status" == "FAIL" ]]; then
    FAILURES=$((FAILURES + 1))
  fi
}

normalize_arches() {
  printf '%s\n' "$1" \
    | tr ',' ' ' \
    | tr ' ' '\n' \
    | sed '/^[[:space:]]*$/d' \
    | LC_ALL=C sort \
    | paste -sd' ' -
}

hash_path() {
  python3 - "$1" <<'PY'
import hashlib
import os
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
h = hashlib.sha256()
if path.is_file():
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
elif path.is_dir():
    root = path.resolve()
    files = sorted(p for p in root.rglob('*') if p.is_file())
    for p in files:
        rel = str(p.relative_to(root)).encode('utf-8')
        h.update(rel)
        h.update(b'\0')
        with p.open('rb') as f:
            for chunk in iter(lambda: f.read(1024 * 1024), b''):
                h.update(chunk)
        h.update(b'\0')
else:
    raise SystemExit(2)
print(h.hexdigest())
PY
}

finish() {
  local status="PASS"
  if (( FAILURES > 0 )); then status="FAIL"; fi

  mkdir -p "$(dirname "$RECEIPT_PATH")"
  SHIPCHECK_JSON_STATUS="$status" \
  SHIPCHECK_JSON_ARTIFACT="$ARTIFACT" \
  SHIPCHECK_JSON_TYPE="$ARTIFACT_TYPE" \
  SHIPCHECK_JSON_SHA256="$SHA256" \
  SHIPCHECK_JSON_APP_PATH="$APP_PATH" \
  SHIPCHECK_JSON_BUNDLE_ID="$BUNDLE_ID" \
  SHIPCHECK_JSON_VERSION="$VERSION" \
  SHIPCHECK_JSON_BUILD="$BUILD" \
  SHIPCHECK_JSON_TEAM_ID="$TEAM_ID" \
  SHIPCHECK_JSON_ARCHES="$ARCHITECTURES" \
  SHIPCHECK_JSON_ENTITLEMENTS_SHA256="$ENTITLEMENTS_SHA256" \
  SHIPCHECK_JSON_CHECKS="$CHECKS_FILE" \
  python3 - "$RECEIPT_PATH" <<'PY'
import datetime
import json
import os
import pathlib
import sys

checks = []
with open(os.environ['SHIPCHECK_JSON_CHECKS'], encoding='utf-8') as f:
    for line in f:
        name, status, detail = (line.rstrip('\n').split('\t', 2) + ['', ''])[:3]
        checks.append({'name': name, 'status': status, 'detail': detail})

payload = {
    'schema': 'shipcheck.receipt.v1',
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'status': os.environ['SHIPCHECK_JSON_STATUS'],
    'artifact': os.environ['SHIPCHECK_JSON_ARTIFACT'],
    'artifact_type': os.environ['SHIPCHECK_JSON_TYPE'],
    'sha256': os.environ['SHIPCHECK_JSON_SHA256'],
    'app_path': os.environ['SHIPCHECK_JSON_APP_PATH'],
    'bundle_id': os.environ['SHIPCHECK_JSON_BUNDLE_ID'],
    'version': os.environ['SHIPCHECK_JSON_VERSION'],
    'build': os.environ['SHIPCHECK_JSON_BUILD'],
    'team_id': os.environ['SHIPCHECK_JSON_TEAM_ID'],
    'architectures': os.environ['SHIPCHECK_JSON_ARCHES'].split() if os.environ['SHIPCHECK_JSON_ARCHES'] else [],
    'entitlements_sha256': os.environ['SHIPCHECK_JSON_ENTITLEMENTS_SHA256'],
    'checks': checks,
}
path = pathlib.Path(sys.argv[1])
path.write_text(json.dumps(payload, indent=2, sort_keys=True) + '\n', encoding='utf-8')
PY

  local summary="${GITHUB_STEP_SUMMARY:-}"
  if [[ -n "$summary" ]]; then
    {
      if [[ "$status" == "PASS" ]]; then
        echo "## ✅ ShipCheck PASS"
      else
        echo "## ❌ ShipCheck FAIL"
      fi
      echo
      echo "| Field | Value |"
      echo "| --- | --- |"
      echo "| Artifact | \`$ARTIFACT\` |"
      echo "| SHA-256 | \`$SHA256\` |"
      [[ -n "$BUNDLE_ID" ]] && echo "| Bundle ID | \`$BUNDLE_ID\` |"
      [[ -n "$VERSION" ]] && echo "| Version | \`$VERSION ($BUILD)\` |"
      [[ -n "$TEAM_ID" ]] && echo "| Team ID | \`$TEAM_ID\` |"
      [[ -n "$ARCHITECTURES" ]] && echo "| Architectures | \`$ARCHITECTURES\` |"
      echo
      echo "### Checks"
      echo
      echo "| Check | Result | Detail |"
      echo "| --- | --- | --- |"
      while IFS=$'\t' read -r name result detail; do
        detail="${detail//|/\\|}"
        echo "| $name | $result | $detail |"
      done < "$CHECKS_FILE"
      echo
      echo "Receipt: \`$RECEIPT_PATH\`"
    } >> "$summary"
  fi

  local output="${GITHUB_OUTPUT:-}"
  if [[ -n "$output" ]]; then
    {
      echo "status=$status"
      echo "bundle-id=$BUNDLE_ID"
      echo "version=$VERSION"
      echo "build=$BUILD"
      echo "team-id=$TEAM_ID"
      echo "architectures=$ARCHITECTURES"
      echo "sha256=$SHA256"
      echo "receipt-path=$RECEIPT_PATH"
    } >> "$output"
  fi

  if [[ "$status" == "PASS" ]]; then
    echo "ShipCheck PASS — $ARTIFACT"
    return 0
  fi
  echo "ShipCheck FAIL — $ARTIFACT" >&2
  return 1
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  record "macOS runner" "FAIL" "ShipCheck must run on macOS."
  finish
  exit $?
fi
record "macOS runner" "PASS" "$(sw_vers -productVersion 2>/dev/null || uname -r)"

if [[ -z "$ARTIFACT" || ! -e "$ARTIFACT" ]]; then
  record "Artifact exists" "FAIL" "Path not found: $ARTIFACT"
  finish
  exit $?
fi
record "Artifact exists" "PASS" "$ARTIFACT"

if SHA256="$(hash_path "$ARTIFACT" 2>/dev/null)"; then
  record "Artifact SHA-256" "PASS" "$SHA256"
else
  record "Artifact SHA-256" "FAIL" "Could not hash artifact."
fi

lower="$(printf '%s' "$ARTIFACT" | tr '[:upper:]' '[:lower:]')"
if [[ -d "$ARTIFACT" && "$lower" == *.app ]]; then
  ARTIFACT_TYPE="app"
  APP_PATH="$ARTIFACT"
elif [[ -f "$ARTIFACT" && "$lower" == *.dmg ]]; then
  ARTIFACT_TYPE="dmg"
  MOUNT_POINT="$TMP_DIR/mount"
  mkdir -p "$MOUNT_POINT"
  if hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_POINT" "$ARTIFACT" >/dev/null 2>&1; then
    APP_PATH="$(find "$MOUNT_POINT" -maxdepth 4 -type d -name '*.app' -print -quit 2>/dev/null || true)"
    if [[ -n "$APP_PATH" ]]; then
      record "DMG mount" "PASS" "Found $(basename "$APP_PATH")"
    else
      record "DMG mount" "FAIL" "Mounted successfully but no .app was found."
    fi
  else
    record "DMG mount" "FAIL" "hdiutil could not mount the disk image."
  fi
elif [[ -f "$ARTIFACT" && "$lower" == *.zip ]]; then
  ARTIFACT_TYPE="zip"
  extract="$TMP_DIR/extract"
  mkdir -p "$extract"
  if ditto -x -k "$ARTIFACT" "$extract" >/dev/null 2>&1; then
    APP_PATH="$(find "$extract" -maxdepth 5 -type d -name '*.app' -print -quit 2>/dev/null || true)"
    if [[ -n "$APP_PATH" ]]; then
      record "ZIP extraction" "PASS" "Found $(basename "$APP_PATH")"
    else
      record "ZIP extraction" "FAIL" "Extracted successfully but no .app was found."
    fi
  else
    record "ZIP extraction" "FAIL" "ditto could not extract the archive."
  fi
elif [[ -f "$ARTIFACT" && "$lower" == *.pkg ]]; then
  ARTIFACT_TYPE="pkg"
else
  record "Artifact type" "FAIL" "Supported types are .app, .dmg, .zip, and .pkg."
fi

if [[ "$ARTIFACT_TYPE" == "pkg" ]]; then
  if pkgutil --check-signature "$ARTIFACT" >"$TMP_DIR/pkg-signature.txt" 2>&1; then
    record "Package signature" "PASS" "pkgutil accepted the installer signature."
  else
    record "Package signature" "FAIL" "$(tail -n 3 "$TMP_DIR/pkg-signature.txt" 2>/dev/null | tr '\n' ' ')"
  fi

  if [[ -n "$EXPECTED_BUNDLE_ID$EXPECTED_VERSION$EXPECTED_BUILD$EXPECTED_TEAM_ID$EXPECTED_ARCHITECTURES" ]]; then
    record "App identity expectations" "FAIL" "Bundle/version/team/architecture expectations apply to app-containing artifacts, not bare .pkg files."
  fi

  if is_true "$REQUIRE_GATEKEEPER"; then
    if spctl --assess --type install -vv "$ARTIFACT" >"$TMP_DIR/gatekeeper.txt" 2>&1; then
      record "Gatekeeper" "PASS" "Installer accepted."
    else
      record "Gatekeeper" "FAIL" "$(tail -n 2 "$TMP_DIR/gatekeeper.txt" 2>/dev/null | tr '\n' ' ')"
    fi
  else
    record "Gatekeeper" "SKIP" "Disabled by input."
  fi

  if is_true "$REQUIRE_NOTARIZATION"; then
    if xcrun stapler validate "$ARTIFACT" >"$TMP_DIR/stapler.txt" 2>&1; then
      record "Notarization ticket" "PASS" "Stapled ticket validated."
    else
      record "Notarization ticket" "FAIL" "$(tail -n 3 "$TMP_DIR/stapler.txt" 2>/dev/null | tr '\n' ' ')"
    fi
  else
    record "Notarization ticket" "SKIP" "Disabled by input."
  fi

  if is_true "$LAUNCH_SMOKE"; then
    record "Launch smoke" "SKIP" "Not applicable to .pkg without installing it."
  fi

  finish
  exit $?
fi

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  record "App discovery" "FAIL" "No app bundle available for verification."
  finish
  exit $?
fi
record "App discovery" "PASS" "$APP_PATH"

if codesign --verify --deep --strict --verbose=2 "$APP_PATH" >"$TMP_DIR/codesign-verify.txt" 2>&1; then
  record "Code signature" "PASS" "Strict nested signature verification passed."
else
  record "Code signature" "FAIL" "$(tail -n 3 "$TMP_DIR/codesign-verify.txt" 2>/dev/null | tr '\n' ' ')"
fi

codesign -dv --verbose=4 "$APP_PATH" >"$TMP_DIR/codesign-detail.txt" 2>&1 || true
TEAM_ID="$(awk -F= '/^TeamIdentifier=/{print $2; exit}' "$TMP_DIR/codesign-detail.txt" | tr -d '\r' || true)"

INFO_PLIST="$APP_PATH/Contents/Info.plist"
if [[ -f "$INFO_PLIST" ]]; then
  BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST" 2>/dev/null || true)"
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST" 2>/dev/null || true)"
  BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST" 2>/dev/null || true)"
  EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST" 2>/dev/null || true)"
  record "Info.plist" "PASS" "Bundle ID=$BUNDLE_ID version=$VERSION build=$BUILD"
else
  EXECUTABLE=""
  record "Info.plist" "FAIL" "Contents/Info.plist is missing."
fi

if [[ -n "$EXPECTED_BUNDLE_ID" ]]; then
  if [[ "$BUNDLE_ID" == "$EXPECTED_BUNDLE_ID" ]]; then record "Bundle ID" "PASS" "$BUNDLE_ID"; else record "Bundle ID" "FAIL" "Expected $EXPECTED_BUNDLE_ID, got $BUNDLE_ID"; fi
else
  record "Bundle ID" "PASS" "${BUNDLE_ID:-detected value unavailable}"
fi

if [[ -n "$EXPECTED_VERSION" ]]; then
  if [[ "$VERSION" == "$EXPECTED_VERSION" ]]; then record "Version" "PASS" "$VERSION"; else record "Version" "FAIL" "Expected $EXPECTED_VERSION, got $VERSION"; fi
else
  record "Version" "PASS" "${VERSION:-detected value unavailable}"
fi

if [[ -n "$EXPECTED_BUILD" ]]; then
  if [[ "$BUILD" == "$EXPECTED_BUILD" ]]; then record "Build version" "PASS" "$BUILD"; else record "Build version" "FAIL" "Expected $EXPECTED_BUILD, got $BUILD"; fi
else
  record "Build version" "PASS" "${BUILD:-detected value unavailable}"
fi

if [[ -n "$EXPECTED_TEAM_ID" ]]; then
  if [[ "$TEAM_ID" == "$EXPECTED_TEAM_ID" ]]; then record "Team ID" "PASS" "$TEAM_ID"; else record "Team ID" "FAIL" "Expected $EXPECTED_TEAM_ID, got ${TEAM_ID:-none}"; fi
else
  record "Team ID" "PASS" "${TEAM_ID:-not set (for example, ad-hoc signing)}"
fi

EXE_PATH=""
if [[ -n "${EXECUTABLE:-}" ]]; then
  EXE_PATH="$APP_PATH/Contents/MacOS/$EXECUTABLE"
fi
if [[ -n "$EXE_PATH" && -f "$EXE_PATH" ]]; then
  ARCHITECTURES="$(lipo -archs "$EXE_PATH" 2>/dev/null || true)"
  ARCHITECTURES="$(normalize_arches "$ARCHITECTURES")"
  if [[ -n "$ARCHITECTURES" ]]; then
    record "Architectures" "PASS" "$ARCHITECTURES"
  else
    record "Architectures" "FAIL" "Could not determine architectures for $EXECUTABLE."
  fi
else
  record "Executable" "FAIL" "CFBundleExecutable does not resolve to a file."
fi

if [[ -n "$EXPECTED_ARCHITECTURES" ]]; then
  expected_norm="$(normalize_arches "$EXPECTED_ARCHITECTURES")"
  actual_norm="$(normalize_arches "$ARCHITECTURES")"
  if [[ "$actual_norm" == "$expected_norm" ]]; then
    record "Architecture expectation" "PASS" "$actual_norm"
  else
    record "Architecture expectation" "FAIL" "Expected [$expected_norm], got [$actual_norm]"
  fi
fi

if codesign -d --entitlements :- "$APP_PATH" >"$TMP_DIR/entitlements.plist" 2>/dev/null && [[ -s "$TMP_DIR/entitlements.plist" ]]; then
  ENTITLEMENTS_SHA256="$(shasum -a 256 "$TMP_DIR/entitlements.plist" | awk '{print $1}')"
  record "Entitlements snapshot" "PASS" "$ENTITLEMENTS_SHA256"
else
  record "Entitlements snapshot" "PASS" "No explicit entitlements detected."
fi

if is_true "$REQUIRE_GATEKEEPER"; then
  if spctl --assess --type execute -vv "$APP_PATH" >"$TMP_DIR/gatekeeper.txt" 2>&1; then
    record "Gatekeeper" "PASS" "App accepted."
  else
    record "Gatekeeper" "FAIL" "$(tail -n 2 "$TMP_DIR/gatekeeper.txt" 2>/dev/null | tr '\n' ' ')"
  fi
else
  record "Gatekeeper" "SKIP" "Disabled by input."
fi

if is_true "$REQUIRE_NOTARIZATION"; then
  STAPLE_TARGET="$APP_PATH"
  [[ "$ARTIFACT_TYPE" == "dmg" ]] && STAPLE_TARGET="$ARTIFACT"
  if xcrun stapler validate "$STAPLE_TARGET" >"$TMP_DIR/stapler.txt" 2>&1; then
    record "Notarization ticket" "PASS" "Stapled ticket validated on $(basename "$STAPLE_TARGET")."
  else
    record "Notarization ticket" "FAIL" "$(tail -n 3 "$TMP_DIR/stapler.txt" 2>/dev/null | tr '\n' ' ')"
  fi
else
  record "Notarization ticket" "SKIP" "Disabled by input."
fi

if is_true "$LAUNCH_SMOKE"; then
  if [[ -n "$EXE_PATH" && -x "$EXE_PATH" ]]; then
    open -na "$APP_PATH" >"$TMP_DIR/launch.txt" 2>&1 || true
    sleep 3
    if pgrep -f "$EXE_PATH" >/dev/null 2>&1; then
      record "Launch smoke" "PASS" "App process observed after launch."
      pkill -TERM -f "$EXE_PATH" >/dev/null 2>&1 || true
    else
      record "Launch smoke" "FAIL" "App process was not observed after launch."
    fi
  else
    record "Launch smoke" "FAIL" "Executable unavailable."
  fi
else
  record "Launch smoke" "SKIP" "Disabled by input."
fi

finish
exit $?
