# TouchMac

**Tap the table beside your MacBook — the desk becomes shortcut buttons.**

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

## Requirements

- Apple Silicon MacBook (tested on M1 Pro MacBook Pro; the sensor is present
  on M1 Pro/Max and M2/M3/M4-family MacBook Pros — check with the command in
  [Troubleshooting](#troubleshooting))
- macOS 14+
- Xcode Command Line Tools (`xcode-select --install`) — full Xcode not needed
- Admin password (the sensor's HID device is root-only; see
  [How it works](#how-it-works))

## Quick start

```sh
git clone <this repo>
cd touchmac/app
sh make_app.sh              # builds app/build/TouchMac.app (SwiftPM, release)
open build/TouchMac.app
```

Inside the app:

1. **Start Sensor** — launches the bundled `touchmacd` helper. You'll be asked
   for your admin password once per boot. When the status pill turns green
   ("Sensor live"), samples are flowing.
2. **Assign actions** — click any zone card and pick what a tap should do:
   - Open app (with app picker; the card shows the real app icon)
   - Screenshot (interactive, to clipboard)
   - Volume up / down / mute
   - Play / Pause (system media key)
   - Any shell command
3. **Calibrate each zone** — from the zone's editor, hit **Calibrate** and tap
   that spot on the desk 10 times at your normal tapping strength. Repeat per
   zone. Zones you skip can't be detected.
4. **Tap the desk.** The matched zone card flashes and its action runs. Recent
   detections (with match distance) appear in the footer log.

**Test mode** (header toggle) flashes zones without running actions — use it to
verify calibration before going live. **Enabled** toggle and the menu-bar icon
control detection globally.

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
┌──────────────────────────────┐        ┌──────────────────────────────────┐
│ touchmacd (root)             │  UDP   │ TouchMac.app (user)              │
│                              │ ─────▶ │                                  │
│ · wakes SPU drivers          │ :48291 │ SensorClient  → TapEngine        │
│ · opens accel+gyro HID       │        │   (UDP recv)     (onset detect)  │
│ · parses 22-byte reports     │        │                     ↓            │
│ · sends [kind][x][y][z]      │        │              Classifier (k-NN)   │
│   datagrams to localhost     │        │                     ↓            │
└──────────────────────────────┘        │              ActionRunner        │
                                        │   SwiftUI: zones, calibration,   │
                                        │   menu bar, config JSON          │
                                        └──────────────────────────────────┘
```

- **`touchmacd`** only *emits* sensor data; it never executes anything.
  Actions run inside the user-level app, so a local process spoofing
  datagrams gains nothing it couldn't do by running commands as the user
  directly — that's why the localhost socket is unauthenticated.
- The app launches the helper on demand via an admin-privileges prompt
  (`do shell script … with administrator privileges`). A pidfile at
  `/var/run/touchmacd.pid` prevents duplicate helpers. The helper keeps
  running after the app quits; it dies on reboot.

### Detection pipeline

1. **Gravity removal** — per-axis exponential moving average (time-constant
   0.15 s) subtracts orientation; the residual is the dynamic acceleration.
2. **Onset detection** — when the dynamic magnitude crosses `thresholdG`
   (default 0.04 g) outside a 250 ms refractory window, a tap starts.
3. **Feature window** — for 60 ms, accel and gyro impulses are summed into a
   6-dim vector, normalized to unit length (direction of the vibration), plus
   a 7th dimension: log10 of the peak magnitude. Direction separates
   left/right/front; peak magnitude separates near from far on the same side.
   If the gyro stream stalls, the engine finishes on accel alone rather than
   silently dying.
4. **Classification** — k-NN (k = 3) against your stored calibration taps,
   dimensions z-scored across the whole training set, majority vote. If the
   winning neighbors' mean distance exceeds `maxDistance` the tap is
   rejected — that's what keeps keyboard thumps and desk bumps from firing
   random actions.

All engine timing is wall-clock based, so the logic is sample-rate independent
and fully testable without hardware (`swift run selftest`).

## Configuration

`~/Library/Application Support/TouchMac/config.json` — written by the app,
hand-editable:

| Key           | Default | Meaning                                                        |
|---------------|---------|----------------------------------------------------------------|
| `thresholdG`  | `0.04`  | Onset threshold in g. Lower = more sensitive (and more false positives from typing). |
| `maxDistance` | `6.0`   | k-NN rejection distance in z-score units. Lower = stricter matching. |
| `zones`       | —       | Per zone: `id`, `name`, `action`, `samples` (calibration features). |

Zone actions are stored as tagged JSON, e.g.
`{"action":{"openApp":{"_0":"/Applications/Safari.app"}}}` or
`{"action":{"shell":{"_0":"open -a Notes"}}}`.

## Project layout

```
touchmac/
├── app/                          # the macOS app (SwiftPM, no Xcode)
│   ├── Package.swift             # 4 targets, macOS 14+, Swift 5 language mode
│   ├── make_app.sh               # release build → build/TouchMac.app (ad-hoc signed)
│   ├── Info.plist
│   └── Sources/
│       ├── TouchMacCore/         # platform-free engine, shared + testable
│       │   ├── TapEngine.swift   #   onset detection state machine
│       │   └── Classifier.swift  #   z-scored k-NN with rejection
│       ├── touchmacd/main.swift  # root helper: IOKit HID → UDP
│       ├── selftest/main.swift   # synthetic-stream engine checks
│       └── TouchMac/             # SwiftUI app
│           ├── TouchMacApp.swift #   window + MenuBarExtra
│           ├── AppState.swift    #   wiring: sensor → engine → classifier → actions
│           ├── SensorClient.swift#   UDP listener
│           ├── Model.swift       #   config, zones, TapAction (Codable)
│           ├── ActionRunner.swift#   executes assigned actions
│           └── Views/            #   MainView, ZonePadView, ZoneEditorView,
│                                 #   CalibrationOverlay
├── touchmac.py                   # earlier Python CLI prototype (macimu-based,
├── test_touchmac.py              #   2 zones × 1/2/3-tap counting) + its tests
└── README.md
```

## Verification

```sh
cd app
swift run selftest        # engine + classifier checks, no hardware needed
python3 ../test_touchmac.py   # Python prototype's detector tests
```

`selftest` covers: onset detection above/below threshold, refractory
suppression of tap ringing, detection surviving a dead gyro stream, and
classifier separation of direction and near/far magnitude plus outlier
rejection.

## Troubleshooting

**Does my Mac have the sensor?**

```sh
ioreg -c AppleSPUHIDDevice -r -d1 | grep -c PrimaryUsage
```

Non-zero → present. Intel Macs and the M1 (non-Pro) MacBook Air/Pro 13" don't
expose it.

**"Start Sensor" but status never goes green** — check the helper log:
`cat /var/log/touchmacd.log`. "no SPU accel/gyro devices found" means your
model doesn't expose the sensor; "open failed" usually means it isn't running
as root.

**Taps detected but wrong zone** — recalibrate with more physical distance
between spots, and tap with consistent strength (near/far discrimination
depends on it). Lower `maxDistance` to reject ambiguous taps instead of
guessing.

**Typing triggers taps** — raise `thresholdG` (try 0.06–0.08), or tap harder.
Desk material matters: rigid desks transmit crisper signatures than soft or
padded surfaces.

**Nothing detected at all** — lower `thresholdG`, confirm the green status
pill, and check zones are calibrated (orange "Calibrate" badge = not yet).

## Known limitations

- Prototype-grade zone separation: left/right/front split reliably by
  direction; near/far on the same side rides on tap intensity, which is
  noisier. Six zones is the honest experimental maximum, not a guarantee.
- Helper must be restarted after reboot (one password prompt per boot). No
  launchd auto-start yet.
- The `.app` is ad-hoc signed — fine for local use, not distributable.
- Media key (Play/Pause) uses a synthesized system event; some macOS versions
  gate this behind Accessibility permissions.

## License / credits

Prototype by Sujal Shrestha. Sensor reverse-engineering credit to
[Olivier Bourbonnais](https://github.com/olvvier/apple-silicon-accelerometer)
(macimu) — the helper's report parsing follows his documented format.
