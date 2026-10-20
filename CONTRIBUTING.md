# Contributing to TouchMac

Thanks for wanting to improve TouchMac. This is a small prototype — focused
PRs beat large rewrites.

## Setup

```sh
git clone https://github.com/SuzalShrestha/touchmac.git
cd touchmac/app
swift run selftest    # engine, classifier and config tests, no hardware
sh make_app.sh        # builds build/TouchMac.app
open build/TouchMac.app
```

Requirements: Apple Silicon MacBook, macOS 14+, Xcode or the Command Line Tools.
CI (`.github/workflows/ci.yml`) runs the self-test in debug and release and builds the app on every push.

## What to work on

Good first targets:

- Detection quality (feature design, near/far separation). Measure changes
  against the real-tap fixture in `app/Sources/selftest/Fixture.swift`; add
  fixtures from other Macs and desks.
- Packaging (Developer ID signing, notarization, DMG) for smoother downloads
- More actions (Focus modes, brightness)
- Docs and hardware compatibility reports

Open an issue before large architecture changes.

## Pull requests

1. Keep changes scoped — one concern per PR.
2. Run `swift run selftest` (and `python3 test_touchmac.py` if you touch the Python prototype).
3. Describe *why*, not just *what*. Link issues when relevant.
4. Do not commit `venv/`, `app/.build/`, or `app/build/`.

## Code layout (quick)

| Path | Role |
|------|------|
| `app/Sources/TouchMacCore/` | Platform-free tap engine, classifier, gestures, config model |
| `app/Sources/touchmacd/` | Root helper (LaunchDaemon): HID → UDP, watchdog |
| `app/Sources/TouchMac/` | SwiftUI app, helper installer, actions |
| `app/Sources/selftest/` | Synthetic + real-tap checks |
| `touchmac.py` | Earlier Python CLI prototype |

## License

By contributing you agree your work is licensed under the MIT License
(see [LICENSE](LICENSE)).
