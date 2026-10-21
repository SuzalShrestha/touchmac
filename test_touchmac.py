"""Synthetic-stream check of TapDetector: onset, zone classify, multi-tap grouping."""

from touchmac import DEFAULT_CONFIG, TapDetector

CFG = {
    **DEFAULT_CONFIG,
    "zones": {
        # left taps kick +x accel, right taps kick -x (unit feature vectors)
        "left": [1.0, 0, 0, 0, 0, 0],
        "right": [-1.0, 0, 0, 0, 0, 0],
    },
}
RATE = CFG["sample_rate"]


def feed(det, seconds, spike=None):
    """Feed `seconds` of rest, with an optional (ax_spike_g, n_samples) burst at start."""
    n = int(seconds * RATE)
    for i in range(n):
        ax = 0.0
        if spike and i < spike[1]:
            ax = spike[0]
        det.feed_accel(ax, 0.0, 1.0)  # gravity on z
        det.feed_gyro(0.0, 0.0, 0.0)


def make(groups):
    det = TapDetector(CFG, lambda z, c: groups.append((z, c)))
    feed(det, 1.0)  # settle gravity EMA
    return det


def test_single_taps_left_right():
    groups = []
    det = make(groups)
    feed(det, 0.6, spike=(0.5, 8))  # left tap
    feed(det, 0.6, spike=(-0.5, 8))  # right tap
    feed(det, 0.6)
    det.flush()
    assert groups == [("left", 1), ("right", 1)], groups


def test_double_tap_groups():
    groups = []
    det = make(groups)
    feed(det, 0.2, spike=(0.5, 8))  # tap, then next tap 200ms later (< 400ms gap)
    feed(det, 0.2, spike=(0.5, 8))
    feed(det, 1.0)
    det.flush()
    assert groups == [("left", 2)], groups


def test_below_threshold_ignored():
    groups = []
    det = make(groups)
    feed(det, 0.6, spike=(0.01, 8))  # under 0.04g threshold
    det.flush()
    assert groups == [], groups


def test_gyro_stall_still_detects():
    groups = []
    det = TapDetector(CFG, lambda z, c: groups.append((z, c)))
    for _ in range(int(1.0 * RATE)):  # settle gravity, no gyro at all
        det.feed_accel(0.0, 0.0, 1.0)
    for i in range(int(0.6 * RATE)):  # left tap, gyro stream dead
        det.feed_accel(0.5 if i < 8 else 0.0, 0.0, 1.0)
    det.flush()
    assert groups == [("left", 1)], groups


def test_uncalibrated_single_zone():
    groups = []
    det = TapDetector({**CFG, "zones": {}}, lambda z, c: groups.append((z, c)))
    feed(det, 1.0)
    feed(det, 0.6, spike=(0.5, 8))
    det.flush()
    assert groups == [("any", 1)], groups


if __name__ == "__main__":
    for name, fn in sorted(
        {k: v for k, v in globals().items() if k.startswith("test_")}.items()
    ):
        fn()
        print(f"ok {name}")
    print("all pass")
