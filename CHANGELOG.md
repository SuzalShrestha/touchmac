# Changelog

Every release is listed here and on the [releases page](https://github.com/SuzalShrestha/touchmac/releases).
release-please writes new entries from the conventional commits merged into `main`.

## [0.2.0](https://github.com/SuzalShrestha/touchmac/compare/v0.1.0...v0.2.0) (2026-10-21)


### Features

* authenticate the sensor channel with a Unix socket and peer checks ([5f8eb19](https://github.com/SuzalShrestha/touchmac/commit/5f8eb19c374e4913c7e22b55a73fc564ac25ce19))
* install updates from GitHub Releases inside the app ([5f8eb19](https://github.com/SuzalShrestha/touchmac/commit/5f8eb19c374e4913c7e22b55a73fc564ac25ce19))
* redesign the app and add in-app updates ([5f1756d](https://github.com/SuzalShrestha/touchmac/commit/5f1756d6bc188414cc4ed48552a8570eb34c9d07))
* redesign the app and add in-app updates ([5f8eb19](https://github.com/SuzalShrestha/touchmac/commit/5f8eb19c374e4913c7e22b55a73fc564ac25ce19))
* show the desk as a 3D render with live tap feedback ([5f8eb19](https://github.com/SuzalShrestha/touchmac/commit/5f8eb19c374e4913c7e22b55a73fc564ac25ce19))


### Bug Fixes

* keep page headers and sidebar rows below the toolbar ([5f8eb19](https://github.com/SuzalShrestha/touchmac/commit/5f8eb19c374e4913c7e22b55a73fc564ac25ce19))
* recheck the console user every second in the helper ([5f8eb19](https://github.com/SuzalShrestha/touchmac/commit/5f8eb19c374e4913c7e22b55a73fc564ac25ce19))

## 0.1.0 (2026-07-17)

First open-source release.

### Features

- SwiftUI menu bar app with six desk tap zones.
- Root helper `touchmacd` that streams the accelerometer and gyroscope.
- Actions: open an app, screenshot, volume, play/pause, shell command.
- k-NN classification with outlier rejection.
- `swift run selftest` engine suite.
