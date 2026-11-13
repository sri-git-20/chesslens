# ChessLens

Scan a chess diagram from a book page, a screenshot or a scanned PDF, and get a
real board you can analyze, play out or solve with Stockfish, fully offline.

> Status: early development (milestone M0, app skeleton). Scanning and the
> engine arrive in the next milestones.

## Planned features

- Recognize printed 2D diagrams from the camera, gallery or PDF pages.
- Load every diagram on a book page at once, or only the ones you pick.
- Analyze, play against and solve positions with Stockfish 19, on the phone.
- Save puzzles in collections; export FEN, PGN and board images.
- Light, dark and true-black themes.
- No account, no tracking, no internet needed after install.

## Try the latest development build (Android)

Every push to `main` builds an APK. On your Android phone, open the
[latest development build](https://github.com/sri-git-20/chesslens/releases/tag/dev-latest),
download `chesslens-dev.apk` and open it. Android will ask you to allow
installs from your browser or file manager the first time.

Development builds are signed with a public test key (`ci/dev-debug.keystore`)
so each new build installs over the last one. Store releases use a separate,
private key.

## Repository layout

| Folder | Contents |
| --- | --- |
| `app/` | The Flutter app (Android and iOS) |
| `ci/` | Files used by the cloud builds |
| `docs/` | Privacy policy and other documents |
| `.github/workflows/` | Cloud build definitions |

## Building

Builds run in GitHub Actions. To build locally you need the Flutter SDK
(stable channel) and Android Studio:

```sh
cd app
flutter pub get
flutter test
flutter run
```

## Licence

ChessLens is free software under the
[GNU General Public License v3](LICENSE). It will bundle
[Stockfish](https://stockfishchess.org/) (GPLv3) and packages from the
[Lichess](https://lichess.org/) project (GPLv3).
