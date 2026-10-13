# Changelog

Versions follow Semantic Versioning. GitHub releases use stable `vMAJOR.MINOR.PATCH` tags.

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
