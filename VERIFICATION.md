# Verification status

## Automated checks

`./scripts/check.sh` runs deterministic core checks, owned native process fixtures, actual IOKit idle-sleep/display assertion creation and release, and release-tool tests. `./scripts/package-release.sh` additionally validates the stable version tag, bundle versions, signed app/helper, native architecture, ZIP extraction and SHA-256 checksums.

Before the public-repository preparation, these core/native/IOKit checks passed on macOS 15.6 Apple Silicon with Swift 6.1.2. The release preparation reruns them on the final source tree. GitHub CI checks both native Apple Silicon and Intel; the actual Actions run is the evidence for each architecture, not this document alone.

## Outstanding manual acceptance for 1.1.0

- Delivered GUI interactions, notification approval/delivery and next-login startup.
- Fresh administrative helper registration and authenticated XPC activation.
- Real global-setting mutation and restoration after normal exit, client crash, lease expiry, helper crash and reboot.
- Physical closed-lid network/task continuation on AC and battery without an external display.

On the development machine, replacing an already registered ad-hoc helper caused launchd `EX_CONFIG (78)` / `needs LWCR update`. The final diagnostic client timed out. This does not prove a fresh installation fails, and it does not prove closed-lid operation succeeds. The global SleepDisabled setting remained false; no successful live activation was recorded. Refresh/reinstall the registration through the documented safe upgrade procedure and repeat system acceptance.

An automated hosted build cannot prove physical lid behavior. The initial downloadable builds have no Developer ID certificate or notarization ticket. Ordinary GitHub release status does not remove these limitations.
