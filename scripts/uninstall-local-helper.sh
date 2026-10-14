#!/bin/bash
set -euo pipefail
if [[ "$EUID" -ne 0 || -z "${SUDO_USER:-}" || "$SUDO_USER" == root ]]; then
  echo 'Run with sudo from your signed-in administrator account.' >&2; exit 1
fi
APP="${1:?Pass the installed macOS Toolset.app path}"
CLIENT="$APP/Contents/MacOS/MacOSToolset"
HELPER="$APP/Contents/Library/HelperTools/ClosedLidHelper"
/usr/bin/codesign --verify --strict "$APP"
/usr/bin/codesign --verify --strict "$HELPER"
/usr/bin/sudo -u "$SUDO_USER" "$CLIENT" --closed-lid-validate-installation
/usr/bin/sudo -u "$SUDO_USER" "$CLIENT" --closed-lid-validate-local-registration
BASE='/Library/Application Support/MacOSToolset'
"$HELPER" --prepare-local-directory
umask 077
if ! /usr/bin/shlock -f "$BASE/local-install.pid" -p "$$"; then
  echo 'Another helper installation/removal is running.' >&2; exit 1
fi
trap '/bin/rm -f "$BASE/local-install.pid"' EXIT
if /usr/bin/pgrep -x MacOSToolset >/dev/null; then echo 'Close Toolset before removal.' >&2; exit 1; fi
"$CLIENT" --closed-lid-unregister-for-repair
for SERVICE in system/local.macostoolset.closedlid system/local.macostoolset.closedlid.local; do
  if /bin/launchctl print "$SERVICE" >/dev/null 2>&1; then /bin/launchctl bootout "$SERVICE"; fi
done
"$HELPER" --prepare-local-install
/bin/rm '/Library/LaunchDaemons/local.macostoolset.closedlid.local.plist'
echo 'Local helper unloaded and registration removed after verified sleep restoration.'
echo 'Protected snapshot and trust records are retained for recovery and future updates.'
