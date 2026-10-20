# Security Policy

## Supported versions

TouchMac is an early open-source prototype. The latest release on
[GitHub Releases](https://github.com/SuzalShrestha/touchmac/releases) is the
only supported line.

## Architecture notes

- **`touchmacd`** runs as root solely to open the Apple SPU HID devices. It
  only *emits* accelerometer/gyroscope samples over localhost UDP. It never
  runs shell commands or opens apps.
- **Actions** (open app, shell, media keys, etc.) run inside the user-level
  `TouchMac.app` process under your account.
- The UDP socket is unauthenticated by design: spoofing samples on localhost
  cannot grant more privilege than the user already has. The ping port
  (48292) only tells the helper to keep sending samples.
- **Install location.** Since v0.2.0 the helper is installed once, with an
  admin prompt, to `/Library/PrivilegedHelperTools/com.sujal.touchmacd`
  (owner root:wheel, mode 755) and started by launchd from
  `/Library/LaunchDaemons/com.sujal.touchmacd.plist`. Earlier versions ran the
  helper as root straight from the app bundle, which any process running as
  the user could replace before the next start. Update to v0.2.0 and use
  Settings → Sensor → Reinstall Helper to move to the safe location.
- The install script receives the bundle path as a POSIX-quoted argument, so
  unusual folder names (with spaces or quotes) cannot change the command.

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Email the maintainer via GitHub
([@SuzalShrestha](https://github.com/SuzalShrestha)) with a private
vulnerability report, or use GitHub's **Security → Report a vulnerability**
on this repository if available.

Include:

- Affected version / commit
- Steps to reproduce
- Impact (e.g. unexpected privilege, persistence of root helper)

You should hear back within a few days. Please give us time to patch before
public disclosure.
