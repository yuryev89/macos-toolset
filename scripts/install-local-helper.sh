#!/bin/bash
set -euo pipefail
if [[ "$EUID" -ne 0 || -z "${SUDO_USER:-}" || "$SUDO_USER" == root ]]; then
  echo 'Run with sudo from your signed-in administrator account.' >&2; exit 1
fi
APP="${1:?Pass the installed macOS Toolset.app path}"
CLIENT="$APP/Contents/MacOS/MacOSToolset"
HELPER="$APP/Contents/Library/HelperTools/ClosedLidHelper"
BASE='/Library/Application Support/MacOSToolset'
SNAPSHOT="$BASE/LocalHelper.app"
PLIST='/Library/LaunchDaemons/local.macostoolset.closedlid.local.plist'
LOCAL_SERVICE='system/local.macostoolset.closedlid.local'
/usr/bin/codesign --verify --strict "$APP"
/usr/bin/codesign --verify --strict "$HELPER"
/usr/bin/sudo -u "$SUDO_USER" "$CLIENT" --closed-lid-validate-installation
"$HELPER" --prepare-local-directory
umask 077
if ! /usr/bin/shlock -f "$BASE/local-install.pid" -p "$$"; then
  echo 'Another helper installation/removal is running.' >&2; exit 1
fi
trap '/bin/rm -f "$BASE/local-install.pid"' EXIT
if /usr/bin/pgrep -x MacOSToolset >/dev/null; then
  echo 'Close every running Toolset copy and diagnostic client before installation.' >&2; exit 1
fi
"$CLIENT" --closed-lid-unregister-for-repair
for SERVICE in system/local.macostoolset.closedlid "$LOCAL_SERVICE"; do
  if /bin/launchctl print "$SERVICE" >/dev/null 2>&1; then /bin/launchctl bootout "$SERVICE"; fi
done
# The helper validates every state-directory parent, acquires its exclusive lock,
# and verifies restoration before the installer changes any executable or trust.
"$HELPER" --prepare-local-install
STAGE="$(/usr/bin/mktemp -d "$BASE/.local-install.XXXXXX")"
# All stage/backup paths are beneath the root-owned, non-writable checked directory.
/usr/bin/ditto "$APP" "$STAGE/LocalHelper.app"
if [[ -n "$(/usr/bin/find "$STAGE/LocalHelper.app" -type l -print -quit)" ]]; then
  echo 'Snapshot contains symlinks; refusing privileged installation.' >&2; exit 1
fi
/usr/sbin/chown -R root:wheel "$STAGE/LocalHelper.app"
/bin/chmod -RN "$STAGE/LocalHelper.app"
/bin/chmod -R go-w "$STAGE/LocalHelper.app"
/usr/bin/codesign --verify --strict "$STAGE/LocalHelper.app"
/usr/bin/codesign --verify --strict "$STAGE/LocalHelper.app/Contents/Library/HelperTools/ClosedLidHelper"
if [[ -e "$SNAPSHOT" || -L "$SNAPSHOT" ]]; then
  if [[ -L "$SNAPSHOT" ]]; then echo 'Unsafe snapshot symlink; refusing installation.' >&2; exit 1; fi
  /bin/mv "$SNAPSHOT" "$STAGE/previous.app"
fi
/bin/mv "$STAGE/LocalHelper.app" "$SNAPSHOT"
"$CLIENT" --closed-lid-validate-root-snapshot
"$SNAPSHOT/Contents/Library/HelperTools/ClosedLidHelper" --repair-client-trust
if [[ -L "$PLIST" ]]; then echo 'Unsafe registration symlink; refusing installation.' >&2; exit 1; fi
/usr/bin/install -o root -g wheel -m 644 "$SNAPSHOT/Contents/Resources/local-helper.plist" "$PLIST"
/usr/bin/sudo -u "$SUDO_USER" "$CLIENT" --closed-lid-validate-local-registration
/bin/launchctl bootstrap system "$PLIST"
echo 'Local helper installed. No system security protections were disabled.'
echo 'Reopen the installed Toolset app. To update, close it and rerun this installer.'
