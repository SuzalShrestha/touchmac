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
  cannot grant more privilege than the user already has.

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
