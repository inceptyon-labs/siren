<p align="center"><img src=".github/logo.png" width="128" alt="Siren icon"></p>

# Siren

An Audiobookshelf client for iPhone, iPad and Apple Watch, for a household that shares one server. It plays, downloads and syncs books from your own Audiobookshelf server, and is growing into the rest of the loop: request a book you don't have, see when it arrives, send it to someone in your house, and know what to listen to next.

Siren is coming to the App Store as **Siren Audiobooks**. Support and the privacy policy are at [inceptyon.io/siren](https://inceptyon.io/siren/support).

## Status

Early. Siren's name, icon, identifiers and signing are in, and the inherited tip jar is out. The app still runs the inherited screens; Siren's new screens are in `Siren/Siren/SirenUI/` with demo data, waiting to be wired to the server.

## Requirements

An [Audiobookshelf](https://www.audiobookshelf.org) server. iOS and iPadOS 17 or later, watchOS 10 or later.

## Build it

Xcode 26 or later. Open `Siren/Siren.xcodeproj` and run the `Siren` scheme. Signing uses the Inceptyon Labs team from `Siren/Signing.xcconfig`; put your own team in `Siren/Local.xcconfig` (copy `Local.xcconfig.example`) to build elsewhere.

The demo screens open with a launch argument: `-SirenDemo home` (also `home-sarah`, `household`, `library`, `book`, `send`, `request`, `car`, `player-cover`, `player-map`, `player-voice`, `settings-art`).

Signing in with OpenID Connect needs `siren://oauth` in the server's **Allowed Mobile Redirect URIs** (Settings → Authentication).

## Layout

- `Siren/`: the Xcode project, with the app, Watch app and widget targets.
- `Siren/Siren/SirenUI/`: Siren's new screens.
- `SirenKit/`: Siren's own logic (ReadMeABook, Audible catalog, server admin, household, recommendations).
- `API/`, `Models/`, `PlayerIntents/`: packages inherited from upstream.
- `design/`: logo sources and the progress-art prototypes.

## Contributing

Issues and pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) first: pull requests need the [contributor agreement](CLA.md) line.

## License

Siren started as a fork of an open-source Audiobookshelf client, and uses two licenses:

- **MPL-2.0** ([LICENSE](LICENSE)): every file Siren inherited, Siren's changes to those files included. That's everything not listed below.
- **AGPL-3.0** ([LICENSE-AGPL](LICENSE-AGPL)), copyright Inceptyon Labs LLC: Siren's own code in `Siren/Siren/SirenUI/`, `SirenKit/`, `scripts/` and `design/prototypes/`.

The Siren name, icon and logo are not covered by either license: see [TRADEMARKS.md](TRADEMARKS.md).

Fixes from upstream come in by cherry-pick: see [`docs/upstream-sync.md`](docs/upstream-sync.md).

Siren is not affiliated with the Audiobookshelf project.
