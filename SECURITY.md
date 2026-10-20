# Security Policy

## Supported versions

TouchMac is an early open-source prototype. The latest release on
[GitHub Releases](https://github.com/SuzalShrestha/touchmac/releases) is the
only supported line.

## Architecture notes

- **`touchmacd`** runs as root solely to open the Apple SPU HID devices. It
  only *emits* accelerometer/gyroscope samples to the app. It never
  runs shell commands or opens apps.
- **Actions** (open app, shell, media keys, etc.) run inside the user-level
  `TouchMac.app` process under your account.
- **Sensor channel.** Since v0.2.0 samples travel over a Unix socket at
  `/var/run/com.sujal.touchmacd.sock`, not localhost UDP. Only root can create
  it, and both ends check each other with `getpeereid`: the app accepts only a
  root peer (no fake taps from other processes, accounts or sandboxed apps),
  and the helper streams only to the console user or root (no motion data,
  which can leak keystrokes, to anyone else). The helper checks the console
  user again every second, so a fast user switch cuts off the previous user
  within about 1 s. v0.1.0 used unauthenticated UDP
  on 127.0.0.1:48291; any local process could inject samples or read them.
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
