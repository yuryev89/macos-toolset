# Contributing

macOS 13+, Swift 5.9+ and Apple Command Line Tools are required. There are no third-party Swift dependencies.

```bash
./scripts/check.sh
./scripts/build-app.sh
```

Use branches and pull requests against `main`. Describe the problem, user-visible behavior and validation. Add regression tests for changed behavior; update `CHANGELOG.md`. Release-tool tests use Python's standard-library unittest runner and are included in `check.sh`.

Process tests use owned fixtures only. Do not exercise destructive actions on workplace apps. Keep closed-lid/global-power checks opt-in on a real test machine. Report pending manual checks explicitly.

Do not attach raw private diagnostics to public issues: process names, executable paths and workplace identifiers may be sensitive. Supply a minimal redacted reproduction. Never commit credentials, signing material, local state, application bundles or build caches. Contributions are under the repository's MIT license.

See [RELEASING.md](RELEASING.md) for versioning, CI, signing and the helper upgrade procedure.
