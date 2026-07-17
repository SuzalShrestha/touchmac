#!/usr/bin/env python3
"""touchmac — tap the table beside your MacBook to trigger shortcuts.

Reads the hidden accelerometer+gyroscope in Apple Silicon MacBooks (via macimu)
and turns taps on the desk into configurable actions. Left/right of the laptop
are distinguished by a calibrated vibration signature; 1/2/3 taps multiply the
button count.

Usage (needs sudo — the SPU HID device is privileged):
    sudo ./venv/bin/python touchmac.py calibrate   # one-time: teach left/right
    sudo ./venv/bin/python touchmac.py run         # detect taps, fire actions
    sudo ./venv/bin/python touchmac.py monitor     # print live signal, tune threshold
"""

import json
import math
import os
import pwd
import subprocess
import sys
import time
from pathlib import Path

# ---------------------------------------------------------------- config

def real_user():
    return os.environ.get("SUDO_USER") or pwd.getpwuid(os.getuid()).pw_name


def config_path():
    home = Path(pwd.getpwnam(real_user()).pw_dir)
    return Path(os.environ.get("TOUCHMAC_CONFIG", home / ".config/touchmac/config.json"))


DEFAULT_CONFIG = {
    "sample_rate": 400,
    "threshold_g": 0.04,        # onset threshold on gravity-removed accel magnitude
    "window_ms": 60,            # feature window after onset
    "refractory_ms": 150,       # ignore new onsets this long after one fires
    "multi_tap_gap_ms": 400,    # max gap between taps of one group
    "min_similarity": 0.5,      # cosine sim below this = not a real tap, ignore
    "zones": {},                # filled by calibrate: {"left": [6 floats], "right": [...]}
    "actions": {
        "left.1": "open -a Safari",
        "left.2": "osascript -e 'set volume output volume ((output volume of (get volume settings)) - 10)'",
        "left.3": "screencapture -ic",
        "right.1": "open -a Music",
        "right.2": "osascript -e 'set volume output volume ((output volume of (get volume settings)) + 10)'",
        "right.3": "osascript -e 'tell application \"Music\" to playpause'",
    },
}


def load_config():
    p = config_path()
    if not p.exists():
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(DEFAULT_CONFIG, indent=2))
        u = pwd.getpwnam(real_user())
        os.chown(p.parent, u.pw_uid, u.pw_gid)
        os.chown(p, u.pw_uid, u.pw_gid)
        print(f"wrote default config: {p}")
    user_cfg = json.loads(p.read_text())
    cfg = dict(DEFAULT_CONFIG)
    cfg.update(user_cfg)
    # keep default actions when a hand-edited config lists only a subset
    cfg["actions"] = {**DEFAULT_CONFIG["actions"], **user_cfg.get("actions", {})}
    return cfg


def save_config(cfg):
    config_path().write_text(json.dumps(cfg, indent=2))


# ---------------------------------------------------------------- detector

class TapDetector:
    """Feed accel/gyro samples in; get (zone, tap_count) groups out.

    Time is counted in accel samples (dt = 1/rate) so the logic is
    deterministic and testable without real hardware.
    """

    def __init__(self, cfg, on_group):
        self.rate = cfg["sample_rate"]
        self.threshold = cfg["threshold_g"]
        self.window_n = max(1, int(cfg["window_ms"] / 1000 * self.rate))
        self.refractory_n = int(cfg["refractory_ms"] / 1000 * self.rate)
        self.gap_n = int(cfg["multi_tap_gap_ms"] / 1000 * self.rate)
        self.min_sim = cfg["min_similarity"]
        self.zones = {z: v for z, v in cfg["zones"].items()}
        self.on_group = on_group          # callback(zone, count)
        self.on_tap = None                # optional callback(feature) per raw tap

        self.g_ema = None                 # gravity estimate per axis
        self.n = 0                        # accel sample counter
        self.last_onset = -10**9
        self.collecting = 0               # samples left in feature window
        self.feat = [0.0] * 6             # [ax,ay,az] impulse + [gx,gy,gz] impulse
        self.gyro_collecting = 0
        # pending tap group
        self.group_zone = None
        self.group_count = 0
        self.group_last_n = 0

    def feed_accel(self, x, y, z):
        self.n += 1
        if self.g_ema is None:
            self.g_ema = [x, y, z]
            return
        a = 0.02  # ponytail: fixed EMA gravity filter; swap for macimu.filters kalman if drift shows
        dyn = []
        for i, v in enumerate((x, y, z)):
            self.g_ema[i] += a * (v - self.g_ema[i])
            dyn.append(v - self.g_ema[i])
        mag = math.sqrt(sum(d * d for d in dyn))

        if self.collecting:
            for i in range(3):
                self.feat[i] += dyn[i]
            self.collecting -= 1
            if self.collecting == 0 and self.gyro_collecting == 0:
                self._finish_tap()
        elif self.gyro_collecting and self.n - self.last_onset > 2 * self.window_n:
            # gyro stream stalled: finish on accel alone rather than dying silently
            self.gyro_collecting = 0
            self._finish_tap()
        elif mag > self.threshold and self.n - self.last_onset > self.refractory_n:
            self.last_onset = self.n
            self.feat = [0.0] * 6
            self.collecting = self.window_n
            self.gyro_collecting = self.window_n

        self._maybe_close_group()

    def feed_gyro(self, x, y, z):
        if self.gyro_collecting:
            self.feat[3] += x
            self.feat[4] += y
            self.feat[5] += z
            self.gyro_collecting -= 1
            if self.gyro_collecting == 0 and self.collecting == 0:
                self._finish_tap()

    def _finish_tap(self):
        f = self.feat
        norm = math.sqrt(sum(v * v for v in f)) or 1.0
        unit = [v / norm for v in f]
        if self.on_tap:
            self.on_tap(unit)
        zone = self._classify(unit)
        if zone is None:
            return
        if self.group_count and zone != self.group_zone:
            self._emit_group()  # side changed mid-group: flush, start new
        self.group_zone = zone
        self.group_count += 1
        self.group_last_n = self.n

    def _classify(self, unit):
        if not self.zones:
            return "any"  # uncalibrated: single zone
        best, best_sim = None, -2.0
        for zone, centroid in self.zones.items():
            sim = sum(a * b for a, b in zip(unit, centroid))
            if sim > best_sim:
                best, best_sim = zone, sim
        return best if best_sim >= self.min_sim else None

    def _maybe_close_group(self):
        if self.group_count and self.n - self.group_last_n > self.gap_n:
            self._emit_group()

    def _emit_group(self):
        self.on_group(self.group_zone, self.group_count)
        self.group_zone, self.group_count = None, 0

    def flush(self):
        if self.group_count:
            self._emit_group()


# ---------------------------------------------------------------- IMU loop

def imu_loop(cfg, detector, monitor=False):
    try:
        from macimu import IMU
    except ImportError:
        sys.exit("macimu not installed. Run: ./venv/bin/pip install macimu")
    if os.geteuid() != 0:
        sys.exit("needs root for SPU HID access: rerun with sudo")

    peak = 0.0
    with IMU(accel=True, gyro=True, sample_rate=cfg["sample_rate"]) as imu:
        print("listening... (ctrl-c to stop)")
        while True:
            for s in imu.read_accel():
                detector.feed_accel(s.x, s.y, s.z)
                if monitor and detector.g_ema:
                    dyn = [getattr(s, ax) - g for ax, g in zip("xyz", detector.g_ema)]
                    peak = max(peak, math.sqrt(sum(d * d for d in dyn)))
            for s in imu.read_gyro():
                detector.feed_gyro(s.x, s.y, s.z)
            if monitor:
                bar = "#" * min(60, int(peak * 400))
                print(f"\rpeak {peak:6.3f} g  |{bar:<60}|", end="", flush=True)
                peak *= 0.92
            time.sleep(0.005)


# ---------------------------------------------------------------- commands

def run_action(cfg, zone, count):
    key = f"{zone}.{count}"
    cmd = cfg["actions"].get(key)
    stamp = time.strftime("%H:%M:%S")
    if not cmd:
        print(f"[{stamp}] {key}: no action configured")
        return
    print(f"[{stamp}] {key}: {cmd}")
    user = real_user()
    home = pwd.getpwnam(user).pw_dir
    # run as the logged-in user, not root, so `open` etc. hit their session
    subprocess.Popen(
        ["sudo", "-u", user, "/bin/sh", "-c", cmd],
        env={"HOME": home, "USER": user, "PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"},
    )


def cmd_run(cfg):
    if not cfg["zones"]:
        print("warning: not calibrated — all taps map to zone 'any'. Run calibrate first.")
    det = TapDetector(cfg, lambda z, c: run_action(cfg, z, c))
    imu_loop(cfg, det)


def cmd_monitor(cfg):
    det = TapDetector(cfg, lambda z, c: print(f"\n>> {z} x{c}"))
    det.on_tap = lambda f: print(f"\ntap feature: {[round(v, 2) for v in f]}")
    imu_loop(cfg, det, monitor=True)


def cmd_calibrate(cfg):
    per_zone = 8
    collected = {}

    for zone in ("left", "right"):
        input(f"\nCalibrating '{zone}': tap the table on the {zone.upper()} side "
              f"{per_zone} times, ~1s apart. Press enter to start...")
        feats = []
        det = TapDetector({**cfg, "zones": {}}, lambda z, c: None)
        det.on_tap = lambda f, fs=feats: (fs.append(f), print(f"  tap {len(fs)}/{per_zone}"))
        try:
            from macimu import IMU
            with IMU(accel=True, gyro=True, sample_rate=cfg["sample_rate"]) as imu:
                while len(feats) < per_zone:
                    for s in imu.read_accel():
                        det.feed_accel(s.x, s.y, s.z)
                    for s in imu.read_gyro():
                        det.feed_gyro(s.x, s.y, s.z)
                    time.sleep(0.005)
        except ImportError:
            sys.exit("macimu not installed. Run: ./venv/bin/pip install macimu")
        centroid = [sum(f[i] for f in feats) / len(feats) for i in range(6)]
        norm = math.sqrt(sum(v * v for v in centroid)) or 1.0
        collected[zone] = [v / norm for v in centroid]

    lsim = sum(a * b for a, b in zip(collected["left"], collected["right"]))
    print(f"\nleft/right signature similarity: {lsim:.2f} "
          f"({'good separation' if lsim < 0.7 else 'WEAK — sides may confuse; tap closer to the laptop edges'})")
    cfg["zones"] = collected
    save_config(cfg)
    print(f"saved to {config_path()}")


def main():
    cmds = {"run": cmd_run, "calibrate": cmd_calibrate, "monitor": cmd_monitor}
    cmd = sys.argv[1] if len(sys.argv) > 1 else "run"
    if cmd not in cmds:
        sys.exit(f"usage: touchmac.py [{'|'.join(cmds)}]")
    cfg = load_config()
    try:
        cmds[cmd](cfg)
    except KeyboardInterrupt:
        print("\nbye")


if __name__ == "__main__":
    main()
