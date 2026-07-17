# touchmac

Tap the table beside your MacBook — the desk becomes shortcut buttons.

Uses the hidden accelerometer + gyroscope in Apple Silicon MacBooks (SPU HID).
Taps on the desk send a vibration signature through the chassis; a calibrated
k-NN classifier maps each tap to one of **6 desk zones** (2 left, 2 right,
2 in front), each bound to a configurable action.

## macOS app (`app/`)

SwiftUI app + root sensor helper. No Xcode needed (SwiftPM + CLT).

```sh
cd app
sh make_app.sh          # builds app/build/TouchMac.app
open build/TouchMac.app
```

In the app:
1. **Start Sensor** — launches the bundled `touchmacd` helper (admin password
   once per boot; the SPU HID device is root-only). Helper streams samples
   over UDP to 127.0.0.1:48291.
2. Click a zone card → pick its action (open app, screenshot, volume,
   play/pause, shell command).
3. **Calibrate** each zone: 10 taps on that desk spot. Detection uses k-NN
   over your calibration taps, z-scored, with a log-peak-magnitude dimension
   to separate near/far pads on the same side.
4. **Test mode** flashes zones without running actions.

Config: `~/Library/Application Support/TouchMac/config.json`.
Engine checks: `cd app && swift run selftest`.

## Python prototype (root of repo)

Earlier CLI proof of concept using [macimu](https://pypi.org/project/macimu/):
2 zones × 1/2/3-tap counting = 6 buttons.

## Setup

```sh
python3 -m venv venv
./venv/bin/pip install macimu
```

Root is required — the SPU HID device is privileged.

```sh
sudo ./venv/bin/python touchmac.py monitor     # watch live signal, tune threshold
sudo ./venv/bin/python touchmac.py calibrate   # teach left vs right (8 taps each)
sudo ./venv/bin/python touchmac.py run         # detect taps, fire actions
```

## Config

`~/.config/touchmac/config.json` (created on first run). Actions map
`zone.count` to any shell command, run as your user:

```json
"actions": {
  "left.1":  "open -a Safari",
  "left.2":  "osascript -e '...volume down...'",
  "left.3":  "screencapture -ic",
  "right.1": "open -a Music",
  "right.2": "osascript -e '...volume up...'",
  "right.3": "osascript -e 'tell application \"Music\" to playpause'"
}
```

Tuning knobs: `threshold_g` (tap sensitivity — lower = more sensitive),
`multi_tap_gap_ms`, `min_similarity` (raise if false zone matches).

## Test

```sh
python3 test_touchmac.py   # synthetic-stream detector tests, no hardware needed
```

## Status / limits

- Prototype: CLI, not yet a menu-bar app.
- Left/right separation depends on your desk; calibrate reports a similarity
  score — below 0.7 is good separation.
- Typing/trackpad clicks can false-trigger; raise `threshold_g` if so.
