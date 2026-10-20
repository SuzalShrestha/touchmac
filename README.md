# TouchMac

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/SuzalShrestha/touchmac?include_prereleases)](https://github.com/SuzalShrestha/touchmac/releases)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black)](https://github.com/SuzalShrestha/touchmac)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-required-lightgrey)](https://github.com/SuzalShrestha/touchmac)

**Tap the table beside your MacBook — the desk becomes shortcut buttons.**

Website: **[suzalshrestha.github.io/touchmac](https://suzalshrestha.github.io/touchmac/)**

TouchMac turns the empty desk space around your MacBook into six configurable
tap zones: two on the left, two on the right, two in front. Tap a spot on the
table and TouchMac opens an app, takes a screenshot, changes volume, toggles
music, or runs any shell command you assign.

No extra hardware. It works because Apple Silicon MacBooks ship with a hidden
accelerometer and gyroscope — a tap on the desk sends a vibration through the
chassis that the sensor picks up, and every desk spot produces a slightly
different vibration signature.

```
                 ┌─────────────────────────┐
   [Left Far]    │                         │    [Right Far]
                 │       MacBook Pro       │
   [Left Near]   │      (top-down view)    │    [Right Near]
                 └─────────────────────────┘
                   [Front Left] [Front Right]
```

---

## Download

**[Get TouchMac →](https://github.com/SuzalShrestha/touchmac/releases/latest)**

Or build from source (below). The release binary is ad-hoc signed — after
unzipping, clear quarantine once:

```sh
xattr -cr ~/Downloads/TouchMac.app
open ~/Downloads/TouchMac.app
```

## Requirements

- Apple Silicon MacBook that exposes the SPU accelerometer (tested on an M1 Pro
  MacBook Pro). The app checks this on first launch; see
  [Troubleshooting](#troubleshooting) for the manual check.
- macOS 14+
- Admin password, once (to install the sensor helper; see [How it works](#how-it-works))
- To build: Xcode or the Command Line Tools (`xcode-select --install`)

## Quick start (from source)

```sh
git clone https://github.com/SuzalShrestha/touchmac.git
cd touchmac/app
sh make_app.sh              # builds app/build/TouchMac.app (SwiftPM, release)
open build/TouchMac.app
```

The welcome guide walks you through it:

1. **Hardware check** — confirms the motion sensor is there.
2. **Install the sensor helper** — one password prompt. The helper is a
   LaunchDaemon: it starts with your Mac and restarts itself after sleep or a
   crash. You never start it by hand again.
3. **Permissions (optional)** — Accessibility for media keys, Screen Recording
   for screenshots. Only needed if you use those actions.
4. **Calibrate** — tap each of the six spots 10 times. After each zone you see
   how well TouchMac can tell it apart from the others, and which zone it is
   confused with, if any.

Then click any zone card to choose what a **single tap** and a **double tap**
do. TouchMac lives in the menu bar; closing the window keeps it running.

## Features

| | |
|---|---|
| **Actions** | Open app · open website · run a Shortcuts shortcut · screenshot · volume up/down/mute · play/pause, next, previous · Mission Control · sleep display · any shell command (runs in your login shell, so Homebrew tools work) |
| **Gestures** | Single and double tap per zone: up to 12 buttons. A zone without a double-tap action fires instantly. |
| **Calibration quality** | Leave-one-out accuracy per zone and overall, with the zone each one is mistaken for. Stray taps (a keystroke during calibration) are dropped automatically. |
| **Robust detection** | Threshold rises in noisy conditions; taps while you type or click are ignored; desk ringing never fires twice. |
| **Feedback** | Live signal meter with the current threshold, activity log with every action, unmatched tap and error (missing permission, app not found, failing command). |
| **App** | Onboarding, Sensitivity page (tap strength, matching tolerance), menu-bar mode, launch at login, test mode, single-instance guard. |

## How it works

### The hidden sensor

Apple Silicon MacBooks contain a Bosch IMU managed by the Sensor Processing
Unit (SPU), exposed as undocumented IOKit HID devices (`AppleSPUHIDDevice`,
vendor usage page `0xFF00`, usage 3 = accelerometer, usage 9 = gyroscope).
The devices deliver 22-byte input reports at ~800 Hz: x/y/z as little-endian
int32 at byte offsets 6/10/14, Q16 fixed point (divide by 65536 → g for
accel, deg/s for gyro). Opening these devices requires root.

Prior art: the [Knock](https://www.producthunt.com/products/knock-7) app,
[apple-silicon-accelerometer](https://github.com/olvvier/apple-silicon-accelerometer)
/ [macimu](https://pypi.org/project/macimu/) by Olivier Bourbonnais.

### Architecture

```
┌────────────────────────────────────┐        ┌──────────────────────────────────┐
│ touchmacd  (root, LaunchDaemon)    │  UDP   │ TouchMac.app (user)              │
│                                    │ ─────▶ │                                  │
│ · wakes SPU drivers                │ :48291 │ SensorClient → TapEngine         │
│ · opens accel+gyro HID             │        │                   ↓              │
│ · sends [kind][x][y][z] datagrams  │ ◀───── │  Classifier (k-NN) → TapGrouper  │
│   only while the app pings         │ :48292 │                   ↓              │
│ · exits on stall → launchd restart │  ping  │             ActionRunner         │
└────────────────────────────────────┘        └──────────────────────────────────┘
```

- **`touchmacd`** only *emits* sensor data; it never executes anything.
  Actions run inside the user-level app, so a local process spoofing
  datagrams gains nothing it couldn't do by running commands as the user
  directly — that's why the localhost socket is unauthenticated.
- The app installs it once: the binary is copied to
  `/Library/PrivilegedHelperTools/com.sujal.touchmacd` (root-owned) and a
  plist to `/Library/LaunchDaemons/com.sujal.touchmacd.plist`. The root
  binary never runs from the user-writable app bundle.
- **Sleep and stalls:** if no sensor report arrives for 5 s, the helper exits
  and launchd restarts it, which wakes the SPU again. At boot it retries for
  30 s before deciding the Mac has no sensor.
- **Energy:** the helper sends only while the app pings it (once a second).
- Settings → Sensor shows the helper state and has Reinstall, Restart,
  Uninstall and Show Log. The app also detects an outdated helper after an update.

### Detection pipeline

1. **Gravity removal** — per-axis exponential moving average (time constant
   0.15 s). The estimate is frozen during a tap and its ringing, so a strong
   tap cannot leak into it and fire a phantom second tap.
2. **Onset detection** — the dynamic magnitude crosses the threshold outside
   a 150 ms refractory window. The threshold is `thresholdG`, raised to
   6× the background noise when the desk is busy (`adaptiveThreshold`).
3. **Feature window** — for 60 ms, accel and gyro impulses are summed into a
   6-dim vector, normalized to unit length, plus a 7th dimension: log10 of the
   peak magnitude. If the gyro stream stalls, the engine finishes on accel alone.
4. **Input filter** — a tap within 0.35 s of a keystroke or click is ignored
   (`ignoreWhileTyping`; reads system idle time, no permission needed).
5. **Classification** — k-NN (k = 3) against your calibration taps, z-scored
   dimensions, majority vote; rejected if the winning neighbors are further
   than `maxDistance`.
6. **Gestures** — a second tap on the same zone within 0.45 s is a double tap.

All engine timing is wall-clock based, so the logic is sample-rate independent
and fully testable without hardware (`swift run selftest`).

## Configuration

`~/Library/Application Support/TouchMac/config.json` — written by the app,
hand-editable. Missing keys take their defaults and an unknown action becomes
"not set", so a file from an older or newer version never loses your
calibration. An unreadable file is moved aside as `config.broken-<date>.json`
and the app tells you; it is never overwritten.

| Key                 | Default | Meaning |
|---------------------|---------|---------|
| `thresholdG`        | `0.04`  | Minimum onset threshold in g ("Tap strength"). |
| `adaptiveThreshold` | `true`  | Raise the threshold while background vibration is high. |
| `ignoreWhileTyping` | `true`  | Ignore taps right after a keystroke or click. |
| `maxDistance`       | `6.0`   | k-NN rejection distance in z-score units ("Tolerance"). |
| `zones`             | —       | Per zone: `id`, `name`, `action`, `doubleAction`, `samples`. |

Actions are tagged JSON, e.g. `{"openApp":{"_0":"/Applications/Safari.app"}}`,
`{"shortcut":{"_0":"Focus"}}` or `{"volumeUp":{}}`.

## Project layout

```
touchmac/
├── app/                          # the macOS app (SwiftPM, no Xcode project)
│   ├── Package.swift             # 4 targets, macOS 14+, Swift 5 language mode
│   ├── make_app.sh               # release build → build/TouchMac.app (ad-hoc signed)
│   ├── Info.plist, AppIcon.icns
│   ├── tools/make_icon.swift     # renders the app icon
│   └── Sources/
│       ├── TouchMacCore/         # platform-free, tested
│       │   ├── TapEngine.swift   #   onset detection, adaptive threshold
│       │   ├── Classifier.swift  #   k-NN, leave-one-out quality, outlier pruning
│       │   ├── TapGrouper.swift  #   single / double tap
│       │   └── Model.swift       #   config, zones, actions (lenient Codable)
│       ├── touchmacd/main.swift  # root helper: IOKit HID → UDP, watchdog
│       ├── selftest/             # engine/config checks + real-tap fixture
│       └── TouchMac/             # SwiftUI app
│           ├── AppState.swift    #   sensor → engine → classifier → gestures → actions
│           ├── Helper.swift      #   LaunchDaemon install / update / uninstall
│           ├── SensorClient.swift, ActionRunner.swift, TouchMacApp.swift
│           └── Views/            #   Desk, Sensitivity, Activity, Settings,
│                                 #   Onboarding, zone editor, calibration
├── docs/                         # product website (GitHub Pages)
├── .github/workflows/ci.yml      # build + self-test on every push
├── touchmac.py, test_touchmac.py # earlier Python CLI prototype + its tests
└── README.md
```

## Verification

```sh
cd app
swift run selftest              # no hardware needed
swift run -c release selftest   # same checks; they use precondition, so they stay on
python3 ../test_touchmac.py     # Python prototype's detector tests
```

`selftest` covers onset detection, refractory vs. double-tap spacing, a dead
gyro stream, the adaptive threshold in noise, classifier separation and
rejection, outlier pruning, single/double gestures, config upgrades
(missing keys, unknown actions, corrupt file), and a **regression floor on
60 real calibration taps** from an M1 Pro (leave-one-out accuracy must stay
≥ 80 %; v0.1.0 measured 83 %).

## Troubleshooting

**Does my Mac have the sensor?**

```sh
ioreg -c AppleSPUHIDDevice -r -d1 | grep -c PrimaryUsage
```

Non-zero → present. Intel Macs and the M1 (non-Pro) MacBook Air/Pro 13" don't
expose it.

**Status stays "Waiting for the sensor"** — open Settings → Sensor → Show Log
(`/var/log/touchmacd.log`). "no SPU accel/gyro devices" means your model does
not expose the sensor; "open failed" means it could not open the device.
Try Restart Helper, then Reinstall Helper.

**Taps detected but wrong zone** — check the accuracy badges on the Desk page.
Recalibrate the zones that are mixed up, with more distance between the spots
and a steady tap strength. Lower *Tolerance* to ignore unclear taps instead of
guessing.

**Typing or the trackpad triggers taps** — keep *Ignore taps while typing or
clicking* on, and raise *Tap strength*.

**Nothing detected** — watch the live signal on the Sensitivity page while you
tap. If the bars stay under the orange line, lower *Tap strength*.

**An action does nothing** — the Activity page shows why (for example a
missing permission or an app that moved).

**Build fails with "plugin for module 'SwiftUIMacros' not found"** — the
Command Line Tools 27 SDK lacks SwiftUI's macro plugin. `make_app.sh` falls
back to the 26 SDK the tools also ship. With plain `swift build`, run
`SDKROOT=$(xcode-select -p)/SDKs/MacOSX26.sdk swift build`, or use Xcode.

**"App is damaged" / can't open the download** — run
`xattr -cr /path/to/TouchMac.app`, then open again.

**Remove everything** — Settings → Sensor → Uninstall, then delete the app
and `~/Library/Application Support/TouchMac`.

## Known limitations

- Prototype-grade zone separation: left/right/front split reliably by
  direction; near/far on the same side rides on tap intensity, which is
  noisier. The calibration score tells you how well it works on your desk.
- The `.app` is ad-hoc signed, not notarized. macOS ties privacy permissions
  to the signature, so after rebuilding you may need to grant them again.
- Media keys use a synthesized system event and need Accessibility permission.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Security reports: [SECURITY.md](SECURITY.md).

## License

MIT — see [LICENSE](LICENSE).

Prototype by [Sujal Shrestha](https://github.com/SuzalShrestha). Sensor
reverse-engineering credit to
[Olivier Bourbonnais](https://github.com/olvvier/apple-silicon-accelerometer)
(macimu) — the helper's report parsing follows his documented format.
