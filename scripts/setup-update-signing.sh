#!/bin/sh
# One-time maintainer setup for signed in-app updates.
#  1. creates the EdDSA key pair in your login keychain, or reuses the one there
#  2. writes the public key into app/Info.plist (commit that change)
#  3. stores the private key as the SPARKLE_PRIVATE_KEY secret of the GitHub repo
# Keep a backup of the private key: without it, no installed copy accepts a new update.
set -e
cd "$(dirname "$0")/.."
BIN=app/.build/artifacts/sparkle/Sparkle/bin
[ -x "$BIN/generate_keys" ] || { echo "run 'sh app/make_app.sh' first, it downloads the Sparkle tools"; exit 1; }

"$BIN/generate_keys" >/dev/null   # creates the key if there is none, never replaces one
PUB=$("$BIN/generate_keys" -p)
# sed, not PlistBuddy: PlistBuddy rewrites the file and drops the release-please markers
sed -i '' "/<key>SUPublicEDKey<\/key>/{n;s|<string>.*</string>|<string>$PUB</string>|;}" app/Info.plist
echo "SUPublicEDKey set to $PUB"

KEY=$(mktemp)
trap 'rm -f "$KEY"' EXIT
rm -f "$KEY" && "$BIN/generate_keys" -x "$KEY"
gh secret set SPARKLE_PRIVATE_KEY < "$KEY"
echo "SPARKLE_PRIVATE_KEY stored in GitHub. Commit app/Info.plist; the next release is signed."
