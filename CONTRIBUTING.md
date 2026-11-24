# Contributing to Siren

Thanks for helping. Bug fixes, especially for playback, downloads and sync against real Audiobookshelf servers, are the most useful contributions.

## Before you start

- For anything bigger than a fix, open an issue first and describe the change, so we can agree on it before you write it.
- Every pull request needs the Contributor License Agreement line in its description (see [CLA.md](CLA.md)). The agreement is what lets Inceptyon Labs also ship your change in the App Store version. You keep the copyright.
- Forks that ship need their own name and icon ([TRADEMARKS.md](TRADEMARKS.md)).

## Building

See [README.md](README.md#build-it). After cloning, install the git hooks once with [pre-commit](https://pre-commit.com) (`brew install pre-commit swift-format gitleaks`). They format Swift and run [gitleaks](https://github.com/gitleaks/gitleaks) on every commit:

```bash
pre-commit install
```

After changing code, run a compile check:

```bash
xcodebuild -project Siren/Siren.xcodeproj -scheme Siren -configuration Debug \
  -destination 'generic/platform=iOS Simulator' build
```

## How the code is written

- Two licenses, by folder (see [README.md](README.md#license)). New features go in new files under `Siren/Siren/SirenUI/` or `SirenKit/`. Keep changes to the MPL files small and mark them with `// SIREN:`, so fixes from upstream still apply.
- New SwiftUI views bind to the existing view models (`*Model.swift`) instead of copying their logic.
- New third-party code must be compatible with the AGPL, the MPL and App Store distribution.
- Keep a pull request to one change.

## Reporting a security problem

Use the private form described in [SECURITY.md](SECURITY.md), not an issue.

## Code of conduct

The project follows the [Contributor Covenant](CODE_OF_CONDUCT.md).
