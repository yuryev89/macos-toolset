#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="$(python3 scripts/release.py metadata --field version)"
TAG="${1:-v$VERSION}"
python3 scripts/release.py metadata --tag "$TAG"
python3 scripts/release.py notes "$VERSION" >/dev/null
ARCH="$(uname -m)"
case "$ARCH" in arm64|x86_64) ;; *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;; esac
./scripts/build-app.sh
APP="$ROOT/dist/macOS Toolset.app"
STAGE="$(mktemp -d "$ROOT/.build/release-package.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    [[ "${CODE_SIGN_IDENTITY:--}" != "-" ]] || { echo 'Notarization requires Developer ID signing' >&2; exit 1; }
    codesign --display --verbose=2 "$APP" 2>&1 | /usr/bin/grep -q 'Authority=Developer ID Application:' || { echo 'Developer ID Application certificate required' >&2; exit 1; }
    ditto -c -k --keepParent "$APP" "$STAGE/submission.zip"
    xcrun notarytool submit "$STAGE/submission.zip" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 30m
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    spctl --assess --type execute --verbose "$APP"
fi
mkdir -p dist/release
NAME="macOS-Toolset-$VERSION-$ARCH"
ZIP="$ROOT/dist/release/$NAME.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
# Check the distributed bytes after an actual archive round trip.
ditto -x -k "$ZIP" "$STAGE/extracted"
EXTRACTED="$STAGE/extracted/macOS Toolset.app"
codesign --verify --strict "$EXTRACTED"
codesign --verify --strict "$EXTRACTED/Contents/Library/HelperTools/ClosedLidHelper"
for EXECUTABLE in "$EXTRACTED/Contents/MacOS/MacOSToolset" "$EXTRACTED/Contents/Library/HelperTools/ClosedLidHelper"; do
    [[ "$(lipo -archs "$EXECUTABLE")" == "$ARCH" ]] || { echo 'Artifact architecture mismatch' >&2; exit 1; }
done
python3 - "$NAME" "$TAG" <<'PY'
import json, os, plistlib, subprocess, sys
from pathlib import Path
name, tag = sys.argv[1:]
info = plistlib.loads(Path('dist/macOS Toolset.app/Contents/Info.plist').read_bytes())
source = plistlib.loads(Path('Info.plist').read_bytes())
assert info['CFBundleShortVersionString'] == source['CFBundleShortVersionString']
assert info['CFBundleVersion'] == source['CFBundleVersion']
commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
dirty = bool(subprocess.check_output(['git', 'status', '--porcelain'], text=True).strip())
manifest = {'tag': tag, 'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'], 'architecture': os.uname().machine, 'minimum_macos': info['LSMinimumSystemVersion'], 'commit': commit, 'working_tree_dirty': dirty, 'signing': 'ad-hoc' if os.environ.get('CODE_SIGN_IDENTITY', '-') == '-' else 'certificate', 'notarized': bool(os.environ.get('NOTARY_PROFILE')), 'closed_lid_end_to_end_verified': False}
Path('dist/release/' + name + '.json').write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
PY
python3 scripts/release.py checksums "dist/release/$NAME.zip" "dist/release/$NAME.json" > "dist/release/$NAME.sha256"
printf 'Packaged: %s\n' "$ZIP"
