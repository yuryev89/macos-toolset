# Security

The process monitor works locally and requires explicit confirmation before parent-process actions. The opt-in sleep helper runs with system privileges only after macOS approval, authenticates exact signed clients and records restoration data in a protected directory.

Please report vulnerabilities through [GitHub private vulnerability reporting](https://github.com/yuryev89/macos-toolset/security/advisories/new) when the owner has enabled it. Do not publish exploit details or private diagnostics in ordinary issues. If private reporting is not available, ask for a private reporting channel without including the vulnerability details.

Only the latest public version is maintained. Version 1.1.0 has outstanding end-to-end helper acceptance; its release notes describe the limits. Disable closed-lid mode and confirm sleep restoration before unregistering the helper or replacing the app. Never remove a pending recovery journal to hide an error.
