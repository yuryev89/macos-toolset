#!/bin/bash
set -euo pipefail
if [[ "$EUID" -ne 0 || -z "${SUDO_USER:-}" || "$SUDO_USER" == root ]]; then
  echo 'Run this explicitly with sudo from the signed-in user account; close Toolset first.' >&2
  exit 1
fi
APP="${1:?Pass the installed macOS Toolset.app path}"
HELPER="$APP/Contents/Library/HelperTools/ClosedLidHelper"
CLIENT="$APP/Contents/MacOS/MacOSToolset"
# Verify both components before stopping this app's service. Never change OS security settings.
/usr/bin/codesign --verify --strict "$APP"
/usr/bin/codesign --verify --strict "$HELPER"
/usr/bin/sudo -u "$SUDO_USER" "$CLIENT" --closed-lid-validate-installation
"$CLIENT" --closed-lid-unregister-for-repair
SERVICE='system/local.macostoolset.closedlid'
if /bin/launchctl print "$SERVICE" >/dev/null 2>&1; then
  /bin/launchctl bootout "$SERVICE"
fi
# The helper refuses concurrent service access and changes trust only after verified recovery.
# No shell command deletes trust.json or recovery.json.
"$HELPER" --repair-client-trust
/usr/bin/sudo -u "$SUDO_USER" "$CLIENT" --closed-lid-register
echo 'Registration refreshed. Approve the helper in macOS if requested, then reopen the installed app.'
