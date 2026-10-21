# Contributing to TouchMac

Thanks for helping. Small, focused pull requests are easiest to review.
Open an issue first for a large change, so we can agree on the direction.

## Setup

```sh
git clone https://github.com/SuzalShrestha/touchmac.git
cd touchmac
npm install           # lint and format tools, and the git hooks (needs Node 20+)
cd app
swift run selftest    # engine, classifier and config tests, no hardware needed
sh make_app.sh        # builds build/TouchMac.app
open build/TouchMac.app
```

Requirements: Apple Silicon MacBook, macOS 14+, Xcode or the Command Line Tools.
`make_app.sh` picks the macOS 26 SDK when the installed Command Line Tools lack the SwiftUI macro plugin.

## Tools

| Command             | What it does                                                            |
| ------------------- | ----------------------------------------------------------------------- |
| `npm run lint`      | oxlint and eslint (website JavaScript), swift-format, ruff, prettier    |
| `npm run format`    | formats everything                                                      |
| `npm test`          | Swift self-test and the Python prototype tests                          |
| `npm run snapshots` | renders every screen, light and dark, to `docs/screens/` with demo data |

The git hooks (husky) format the files you stage and check your commit message.
CI runs the same checks on every pull request (`.github/workflows/ci.yml`).

Snapshot mode (`TouchMac --snapshot <dir>`) never connects to the sensor and never writes your settings.
Use it for before and after pictures of UI changes. It also warns when a page is taller than the window.

## Commit messages

Use [conventional commits](https://www.conventionalcommits.org/). The type sets the changelog section and the next version:

- `feat: add brightness actions` → new minor version, under Features
- `fix: keep the helper alive after sleep` → new patch version, under Bug Fixes
- `docs:`, `refactor:`, `test:`, `ci:`, `chore:` → no release on their own

Pull requests are squash-merged, so the PR title must follow the same rule.

## How a release happens

1. Every merge to `main` updates an open "chore: release x.y.z" pull request.
   It holds the new `CHANGELOG.md` entry and the new version in `app/Info.plist`.
2. Merging that pull request tags the release. The release workflow builds the app,
   zips it, signs the zip with the update key, and attaches the zip and `appcast.xml`.
3. Installed copies find the new `appcast.xml` and offer the update.

One-time maintainer setup for signed updates: `sh scripts/setup-update-signing.sh`.
It creates the EdDSA key in the keychain, writes the public key to `app/Info.plist`,
and stores the private key as the `SPARKLE_PRIVATE_KEY` repository secret.
Keep a backup of that key. Without it, installed copies reject every new update.

## What to work on

- Detection quality (feature design, near and far separation). Measure changes against the real-tap
  fixture in `app/Sources/selftest/Fixture.swift`, and add fixtures from other Macs and desks.
- Developer ID signing and notarization, so the first download needs no `xattr`.
- More actions (Focus modes, brightness).
- Hardware reports: use the "Hardware report" issue form.

## Design notes

- Colours, type and buttons live in `app/Sources/TouchMac/Design/Theme.swift`. Each zone has one hue,
  used everywhere that zone appears.
- The desk picture is a SceneKit scene rendered once to an image (`DeskRender.swift`).
  The glows, ripples and calibration dots are SwiftUI views drawn over it at projected positions.
- Respect Reduce Motion. Keep every control reachable with the keyboard and VoiceOver.

## Code layout

| Path                        | Role                                                         |
| --------------------------- | ------------------------------------------------------------ |
| `app/Sources/TouchMacCore/` | Platform-free tap engine, classifier, gestures, config model |
| `app/Sources/touchmacd/`    | Root helper (LaunchDaemon): HID → Unix socket, watchdog      |
| `app/Sources/TouchMac/`     | SwiftUI app, helper installer, actions, updater              |
| `app/Sources/selftest/`     | Synthetic and real-tap checks                                |
| `docs/`                     | Product website (GitHub Pages)                               |
| `touchmac.py`               | Earlier Python CLI prototype                                 |

## License

By contributing you agree that your work is licensed under the MIT License (see [LICENSE](LICENSE)).
Please follow the [code of conduct](CODE_OF_CONDUCT.md).
