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

## Helper registration repair in 1.1.1

The affected machine's app was running from App Translocation while launchd repeatedly failed to spawn a stale helper registration with `EX_CONFIG (78)` and `needs LWCR update`. The global SleepDisabled setting remained false.

New regression checks first failed, then passed after implementing installed-location validation, recovery-before-trust-rebinding, and an exclusive recovery-directory lock. The full local check suite, real owned process fixtures, IOKit assertion checks, and app/helper bundle build pass. Running the built app from its build directory is rejected with installation instructions; unprivileged administrative unregister is rejected before ServiceManagement mutation.

An independent code review identified an unsafe unprivileged refresh/unregister path, which was removed. Registration-only commands cannot stop a helper; administrative interruption requires the explicit root-attended repair script. The reviewer found no remaining Critical/Important issues in those boundaries.

On 2026-10-14, the administrator executed the installed repair script. Administrative unregister, recorded-baseline restoration, and exact client trust rebinding succeeded. Subsequent registration via `sudo -u` failed with Operation not permitted. Running registration directly from the ordinary user session succeeded, and launchd reported bundle build 3.

The newly registered helper then failed with `OS_REASON_CODESIGNING / Launch Constraint Violation`. AMFI explicitly reported `AppleMobileFileIntegrityError -423`: the file was ad-hoc signed or signed by an unknown certificate chain. No valid code-signing identities are installed. Thus stale registration was one problem, but ad-hoc signing also prevents live helper activation on this tested Mac. Restoration succeeded and SleepDisabled remained false. The script now ends after successful recovery and prints the separate user-session registration step.

Live activation, crash/lease/reboot restoration, and physical closed-lid tests remain blocked by the signing requirement. They must not be marked as passed based on successful registration or unit tests.

## Administrator-managed local helper

An alternative classic LaunchDaemon installation is implemented for local use without an Apple Developer account. It preserves the existing authenticated XPC, journal, and lease logic, while deploying a sanitized root-owned snapshot and separate protected launchd plist. SIP and Gatekeeper are not disabled.

Configuration/marker tests first failed with nine assertions, then passed after validating fixed executable/service fields and root-owned, non-writable, non-symlink records. A further test exposed missing executable ownership validation. The fix sanitizes ACLs/permissions before privileged execution and checks the root executable and ancestors; positive validation uses the actual root-owned `/bin/launchctl` file. macOS returns ENOENT from acl_get_fd_np on an existing descriptor with no ACL; this behavior was verified by read-only probes and handled explicitly.

Full local core/native/IOKit checks and the bundle build are rerun on the final tree. Privileged installation, root XPC activation, restoration, and physical lid checks remain pending until actually exercised.
