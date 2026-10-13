# Release process

Repository: [yuryev89/macos-toolset](https://github.com/yuryev89/macos-toolset). The default branch is `main`. Only stable tags of the form `vMAJOR.MINOR.PATCH` are released; there is no release-candidate track.

## Routine release

1. Create a branch from `main` and make the changes.
2. Run `python3 scripts/release.py bump 1.1.1` with the intended next version. This increases the app build number and rejects old versions and prerelease suffixes.
3. Add the matching dated section to `CHANGELOG.md`. State user-visible changes, verification and known limitations accurately. Update the matching verification document when new system tests are actually performed.
4. Run `./scripts/check.sh` and `./scripts/package-release.sh v1.1.1`. Inspect the archive, architecture, signatures, metadata and checksums under `dist/release/`. A local build's metadata indicates whether its working tree was dirty.
5. Merge the reviewed change into `main` after both architecture checks pass. Never commit diagnostics, signing keys or notarization credentials.
6. Create and push the tag on that exact commit:

   ```bash
   git switch main
   git pull --ff-only
   git tag -a v1.1.1 -m 'macOS Toolset 1.1.1'
   git push origin v1.1.1
   ```

7. The Release workflow checks version/tag agreement, repeats tests, builds and verifies native `arm64` and `x86_64` bundles, checks ZIP extraction and generates checksums. It creates a temporary draft while attaching all assets, then publishes an ordinary release and marks it Latest. Both architecture jobs must succeed. The temporary draft is not a prerelease or release candidate.
8. Verify both ZIP files, metadata and `SHA256SUMS` are visible in the release. Download a published archive, verify its hash and test installation/update on a real Mac.

Release workflow failure does not publish an incomplete release. Rerun the failed run, or use the workflow's manual input with the existing stable tag. Published releases cannot be overwritten by this workflow; corrections use a new patch version. Do not move an already published tag or silently replace published binaries.

## CI and permissions

- `CI` runs tests and a full app build for pushes to `main` and pull requests.
- `Release` runs on pushed version tags or manual dispatch. It validates the exact tag checkout.
- Build jobs receive read access only. Only the final publishing job receives `contents: write`; it uses the short-lived repository `GITHUB_TOKEN` supplied by GitHub.
- Actions are pinned to full commit hashes. Dependabot proposes monthly updates.
- There are no signing secrets in ordinary CI and no privileged closed-lid smoke tests on hosted runners.
- In repository settings, protect `main` with the two `Check (arm64)` / `Check (x86_64)` checks once their first run exists. Require reviews when collaborating. Enable private vulnerability reporting under Security. These settings need repository-owner access and are not changed by a file in this repository.

## Signing and notarization

The initial automation deliberately produces ad-hoc signed bundles and states this in release notes and metadata. It does not claim Developer ID signing, notarization or universal end-to-end closed-lid acceptance. A regular GitHub release designation does not imply any of those checks.

For Developer ID distribution, obtain a Developer ID Application certificate with its private key in your macOS Keychain and configure a `notarytool` Keychain profile yourself. Do not commit exported certificates or authentication data. On that trusted Mac:

```bash
export CODE_SIGN_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)'
export NOTARY_PROFILE='YOUR_EXISTING_KEYCHAIN_PROFILE'
./scripts/check.sh
./scripts/package-release.sh v1.1.1
```

Both executables are signed with Hardened Runtime and a timestamp, then the containing app is signed. The package command submits the same app to Apple, waits for notarization, staples and validates the ticket, assesses Gatekeeper and only then creates the final ZIP/checksums. It checks signatures again after extracting the final archive. This path requires existing credentials; it was not exercised for 1.1.0 because the development machine has no Developer ID identity.

Current hosted release jobs do not import these credentials. To adopt signed automation later, use an explicitly approved signing environment and secret storage; do not mix signed local archives with hosted ad-hoc artifacts under one immutable tag. Release the complete signed asset set as a new version after testing installation and helper approval.

Sources: [GitHub hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners), [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Sleep/helper acceptance and upgrades

For changes to the helper, run the opt-in `swift scripts/closed-lid-smoke.swift /Applications/macOS\ Toolset.app/Contents/MacOS/MacOSToolset` on a real test Mac after administrative approval and with the ordinary app closed. Check original SleepDisabled restoration after normal stop, client crash and lease expiry. Also test helper restart, reboot and external overrides. Physical lid closure must be checked with independent SSH/TCP/task observation for at least two minutes on AC and battery, without an external monitor.

Before replacing an installed version: disable closed-lid mode, confirm restoration, and unregister its helper in the **old** app. Install the new app, administratively remove only the old `trust.json` after recovery is complete, then approve the new helper. Never discard pending `recovery.json`. Exact client-signature pinning means new app signatures require this procedure even with a Developer ID certificate. See README recovery instructions if the helper is unavailable.

## Local emergency recovery

If an active helper cannot restore sleep, recover the machine before uninstalling or changing permission. An administrator who wants to allow sleep regardless of the recorded original value may use `sudo /usr/bin/pmset disablesleep 0`. This is a deliberate override, not an automatic release step. Keep recovery data and investigate the cause.
