# Contributing to TouchMac

Thanks for wanting to improve TouchMac. This is a small prototype — focused
PRs beat large rewrites.

## Setup

```sh
git clone https://github.com/SuzalShrestha/touchmac.git
cd touchmac/app
swift run selftest    # engine tests, no hardware
sh make_app.sh        # builds build/TouchMac.app
open build/TouchMac.app
```

Requirements: Apple Silicon MacBook, macOS 14+, Xcode Command Line Tools.

## What to work on

Good first targets:

- Detection quality (threshold defaults, feature design, near/far separation)
- UX: calibration flow, false-positive feedback, onboarding
- launchd helper so the sensor survives reboot without a password re-prompt
- Packaging (notarization, DMG) for smoother downloads
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
| `app/Sources/TouchMacCore/` | Platform-free tap engine + k-NN classifier |
| `app/Sources/touchmacd/` | Root helper: HID → UDP |
| `app/Sources/TouchMac/` | SwiftUI app, actions, config |
| `app/Sources/selftest/` | Synthetic stream checks |
| `touchmac.py` | Earlier Python CLI prototype |

## License

By contributing you agree your work is licensed under the MIT License
(see [LICENSE](LICENSE)).
