# macOS Toolset

[![CI](https://github.com/yuryev89/macos-toolset/actions/workflows/ci.yml/badge.svg)](https://github.com/yuryev89/macos-toolset/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/yuryev89/macos-toolset)](https://github.com/yuryev89/macos-toolset/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A native menu bar utility for macOS 13+, built with Swift/SwiftUI and AppKit.

## Installation

Download from [GitHub Releases](https://github.com/yuryev89/macos-toolset/releases/latest). Choose `arm64` for Apple Silicon or `x86_64` for Intel. To verify your archive, download `SHA256SUMS` and run the following in your download directory (replace `arm64` with `x86_64` for Intel):

```bash
grep -F '  macOS-Toolset-1.1.1-arm64.zip' SHA256SUMS | shasum -a 256 -c -
```

The full command, `shasum -a 256 -c SHA256SUMS`, requires both ZIP archives and both release JSON files in the same directory.

Builds are ad-hoc signed and not notarized, so macOS may block the downloaded app. Do not disable system security protections; you can build the app locally using the instructions below. Developer ID signing and notarization are covered in the [release process](RELEASING.md). Use the version in your downloaded archive's filename when verifying its checksum.

Copy `macOS Toolset.app` to `/Applications`. Before updating, follow the helper removal procedure below. Do not replace the app while closed-lid mode is active.

**Closed-lid status:** the feature is implemented and available in settings, but end-to-end verification of helper activation, system sleep restoration, and continued networking on battery and AC power is still pending. On the development Mac, the old helper registration needs refreshing after its signature changed. The presence of a toggle does not guarantee closed-lid operation. See [verification](VERIFICATION.md).

## Features

- Checks for zombie processes every five minutes inside the app, without launching a shell or `ps`.
- Opens an incident after three consecutive checks find at least 40 zombies under the same parent.
- Local notifications, history and trends, JSON/TXT export for IT, and 30-day retention.
- Parent termination requires explicit confirmation and revalidation of its PID and start time. Force termination is a separate action. Restart is supported only for recognized GUI apps.
- Keep-awake modes for the computer alone or the computer and display, plus an off state; restores the last selection.
- A separate closed-lid mode with a macOS system helper, intended for battery and AC operation without an external monitor. Full verification is pending.
- Registers launch at login on first launch through native ServiceManagement APIs.

A zombie has already exited; sending it a kill signal is ineffective. The app offers actions on its parent, which may interrupt an app or VPN. The process monitor needs no administrator privileges and never terminates processes automatically. The separate system sleep helper requires administrative approval.

## Running the app

Open `/Applications/macOS Toolset.app`. A four-square icon appears in the menu bar. The panel opens on first launch; afterward, open it from the menu or by reopening the app.

The app interface currently uses Russian. The control and status names in this documentation are English translations of those labels.

Allow notifications in the macOS prompt. If launch at login requires approval, open System Settings → General → Login Items. The actual status appears under **Sleep and Settings**. Launch at login explicitly disabled by the user is not automatically re-enabled.

On first launch, the computer is kept awake while the display may turn off. After a change, the selected mode is restored, including the off state. Closing the window leaves the utility running; **Quit** exits and releases its sleep assertions. The selected mode takes effect again on the next launch.

Ordinary IOKit modes do not override lid closure. The separate closed-lid mode uses the system `SleepDisabled` setting to disable system sleep globally, including open-lid sleep and the ordinary Sleep command. Turn this mode off to restore normal sleep. The display may turn off, and screen locking remains available. Battery consumption increases; continued operation after battery depletion or hardware shutdown is not guaranteed.

### Closed-lid operation

Enable **Work with the lid closed** under **Sleep and Settings**. This mode is off by default. On first activation, macOS requires system helper approval: use the corresponding button and allow the helper in System Settings → General → Login Items & Extensions. Return to Toolset afterward. Only the **Active** status confirms that the setting was applied successfully.

The setting is intended for battery and AC power without an external monitor; each scenario requires a physical test. It prevents Mac sleep but cannot prevent external network or VPN outages. The preference is saved for the next app launch, but the helper does not keep sleep disabled without a live app session.

The helper records the original value before changing it, verifies the result, and restores it when the mode is disabled, the app exits, or the connection is lost. The app renews its session every 10 seconds; after 60 seconds without renewal, the helper starts restoration. If the helper crashes, launchd restarts it, and it first recovers any unfinished journal entry. If another utility had already enabled `SleepDisabled`, it remains enabled when this session ends; the app reports that explicitly. A restoration failure is displayed as an error rather than confirmation of normal sleep.

Disable the service or remove the app only after turning off the mode and confirming restoration. Disabling the helper directly in macOS may prevent cleanup. If restoration is incomplete, restore its permission and retry disabling the mode. Only when the helper is unavailable and you want to allow sleep regardless of the original value may an administrator run `sudo /usr/bin/pmset disablesleep 0`.

A local ad-hoc build pins the approved client's exact signature in a root-owned `trust.json`; a new build requires an administrative update of that trust. To update: end the mode, confirm restoration, unregister the helper in Toolset, replace the app, administratively remove only `/Library/Application Support/MacOSToolset/ClosedLid/trust.json`, and approve the helper again. Do not remove `recovery.json` until restoration is confirmed. The trust file contains no keys or passwords.

Optional diagnostics after installation and approval (close the ordinary app first):

```bash
swift scripts/closed-lid-smoke.swift
```

This check enables and disables the mode only through the signed app and checks restoration after app exit and session expiry. It is not part of ordinary `check.sh`. Physical closed-lid testing on battery and AC power is separate and requires independent observation of SSH/TCP connectivity and a running task for at least two minutes.

## Building and checking

### Helper registration repair

If an updated or moved app reports a helper timeout, install it in `/Applications` or `~/Applications` and close all running copies first. Launching from Downloads or App Translocation is unsupported for helper registration. Ordinary monitoring remains available.

Version 1.1.1 adds a repair script inside the signed app. Run it explicitly from your signed-in administrator account, substituting your installed path if needed:

```bash
sudo /bin/bash '/Applications/macOS Toolset.app/Contents/Resources/repair-helper.sh' '/Applications/macOS Toolset.app'
```

The script verifies both signatures, stops only this app's helper, restores the recorded original sleep setting, and pins the installed app's exact signature only after successful restoration. It prints a registration command to run afterward in your ordinary user session, without `sudo`; registration via `sudo -u` was rejected on the affected Mac. Approve the helper in macOS if requested and reopen the installed app. The repair does not enable closed-lid mode itself. It does not delete recovery data before verified restoration, reset other background items, or disable macOS security protections. If recovery fails, the repair stops and preserves the journal and old trust record; address that error before retrying.

**Signing requirement:** successful registration does not imply that macOS will launch the helper. On the affected macOS 15.6 Mac, the freshly registered ad-hoc helper was rejected by AMFI (`AppleMobileFileIntegrityError -423`, launch constraint violation). Both the app and helper need an appropriate stable signing identity for this ServiceManagement path. Apple recommends the same Apple-issued identity for both; Developer ID Application is the distribution path. An ad-hoc GitHub build cannot provide working closed-lid control on this tested system. See [Apple DTS guidance](https://developer.apple.com/forums/thread/799910). No security protections should be disabled to work around this requirement.

For 1.1.0, use the original upgrade/recovery procedure above; its bundle does not contain this script.

## Build requirements and checks

Requires Apple Command Line Tools with Swift 5.9 or later. Full Xcode is not required. There are no external packages.

```bash
./scripts/check.sh
./scripts/build-app.sh
open 'dist/macOS Toolset.app'
```

`check.sh` runs logic checks through the `CoreChecks` executable without XCTest, which is missing from some CLT installations, as well as small C/IOKit smoke tests. The process smoke test creates only its own fixture and zombie child, terminates the parent with a revalidated TERM signal, and cleans up the child. Cisco and other production processes are not used.

The build creates an ad-hoc signed `.app` for local use. Developer ID signing and notarization for distribution to other Macs require your own credentials and are not part of the default local build. Do not run multiple copies of the app from different directories simultaneously.

## Data

Incidents and the action log are stored in `~/Library/Application Support/MacOSToolset/`. Preferences use the `local.macostoolset.app` UserDefaults domain.

Reports contain PIDs, start times, process names and paths, zombie counts, and the action log. Command arguments, environment variables, process memory, and credentials are not collected. Paths may contain the username. No data is transmitted over the network. The app does not delete manually exported copies.

Monitoring continues if notifications are denied; its status remains visible in the menu. Access, export, and system action errors are reported explicitly. Signaling a process by PID has a small, unavoidable gap between identity revalidation and signal delivery; the app does not claim this operation is completely atomic.

## Structure

- `Sources/ToolsetCore`: deterministic incident engine, preferences, diagnostics, and sleep assertion abstraction.
- `Sources/CSnapshot`: system process table and revalidated signaling.
- `Sources/MacOSToolset`: system services, file-work actor, menu, and SwiftUI panel.
- `Tests/ToolsetCoreTests`: executable checks without a third-party testing framework.
- `DESIGN.md`: application design; `RELEASING.md`: release process.

Source code is distributed under [MIT](LICENSE). See [CONTRIBUTING.md](CONTRIBUTING.md) to contribute.

New tools are added as separate modules rather than dynamic plugins.

## System integration references

- [Apple: wait/waitpid](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/wait.2.html)
- [Apple: SMAppService.mainApp](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp)
- [Apple: preventing idle display sleep](https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventuseridledisplaysleep)
- [Apple Darwin: process information](https://github.com/apple/darwin-xnu/blob/main/bsd/sys/proc_info.h)

Detailed verification results and limitations: [VERIFICATION.md](VERIFICATION.md).
