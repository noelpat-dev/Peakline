# Security

Peakline is a personal portfolio project. The app keeps primary workout data in local SwiftData storage and uses passphrase-encrypted Firebase backup only when the optional account feature is configured.

## Reporting a concern

Please do not publish credentials, personal backup data, or an exploit demonstration in a public issue. Contact [Noel through GitHub](https://github.com/noelpat-dev) with a concise description, affected version or commit, reproduction steps, and the smallest safe proof of impact. If GitHub Security Advisories are enabled for the repository, use a private advisory instead.

## Current safety boundaries

- Firebase rules require an authenticated user to access only that user's backup path.
- Backup metadata, encrypted payloads, decompression, record counts, and Firestore chunks have explicit size and count limits.
- The Firebase configuration file and signing material are ignored and must never be committed.
- UI-test launch arguments and fixture seeding are compiled only into Debug builds.
- The current codebase has no known committed credential or confirmed cross-user access path; live Firebase and physical-device validation remain release checks.
