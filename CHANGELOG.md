# Changelog

Versions follow Semantic Versioning. GitHub releases use stable `vMAJOR.MINOR.PATCH` tags.

## [1.1.1] - 2026-10-13

### Fixes

- Reject closed-lid helper registration from Downloads, App Translocation, or other uninstalled locations with actionable installation instructions.
- Add an explicit administrator-attended helper repair for stale registrations after app updates or relocation. The signed app includes `Contents/Resources/repair-helper.sh`; see the README procedure.
- Restore and verify the recorded sleep baseline before updating the exact approved client signature. Failed restoration preserves recovery data and the prior trust record.
- Serialize helper recovery and maintenance with a protected directory lock to prevent concurrent recovery writers.
- Explain helper timeouts and the repair procedure instead of providing only a generic eight-second error.
- Translate all repository documentation into English.

### Verification and limitations

Regression tests exercise installed-location validation, successful and failed recovery before trust changes, and exclusive helper ownership. The local full check suite and signed bundle build pass. Administrative recovery and client trust repair succeeded on the affected Mac. Registration succeeded only from an ordinary user session, without `sudo -u`; macOS then rejected the ad-hoc helper with a launch constraint/code-signing violation. Working closed-lid operation requires appropriate signing and is not provided by the ad-hoc build on this tested system. Physical lid checks remain pending. Builds are not notarized. Read the README before replacing an installation with an active closed-lid session.

## [1.1.0] - 2026-10-13

First public release of macOS Toolset, a native menu bar utility for macOS 13+.

### Features

- Zombie-process monitoring with incident history, notifications and local JSON/TXT export.
- Explicitly confirmed parent-process actions with PID and start-time checks.
- Idle sleep and display sleep controls with owned IOKit assertions.
- A separate, opt-in closed-lid control with an authenticated privileged helper, durable recovery journal and expiring client lease.
- Native Apple Silicon and Intel builds; ZIP archives, SHA-256 checksums and build metadata.

### Verification

Automated core tests, owned process fixtures, real idle-sleep assertions and release-tool tests pass on the development Apple Silicon Mac. GitHub Actions repeats automated checks on both architectures. Check the linked workflow run for actual CI results.

### Known limitations

- Downloadable builds are ad-hoc signed and **not notarized**. They do not have a Developer ID certificate. macOS may prevent opening them; building locally is the supported alternative. Do not disable system security protections to install this release.
- Closed-lid operation is **not yet validated end to end**. The development Mac's registered helper requires a registration refresh after its executable signature changed; authenticated activation, global-setting restoration, crash/reboot recovery, and physical closed-lid operation on AC and battery are pending. This release does not guarantee uninterrupted networking with the lid closed.
- Changing to a new app signature requires restoring sleep, unregistering the old helper and an administrative update of its pinned client identity. See the update procedure in the README.
- The idle-sleep controls do not override lid closure. The closed-lid setting, when active, disables system sleep globally and increases battery use.
- GUI approval dialogs, login after reboot and notification delivery require manual checks.

### License

MIT. Diagnostics stay local unless explicitly exported by the user.
