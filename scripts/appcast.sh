#!/bin/sh
# Writes the Sparkle feed for one release to stdout.
# usage: appcast.sh <version> <zip> <release-notes.html>
# Needs SPARKLE_PRIVATE_KEY (the key text) in the environment.
set -e
VERSION=$1 ZIP=$2 NOTES=$3
BIN=$(dirname "$0")/../app/.build/artifacts/sparkle/Sparkle/bin
SIG=$(printf %s "$SPARKLE_PRIVATE_KEY" | "$BIN/sign_update" --ed-key-file - "$ZIP")  # sparkle:edSignature="…" length="…"
URL="https://github.com/SuzalShrestha/touchmac/releases/download/v$VERSION/$(basename "$ZIP")"
MIN=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$(dirname "$0")/../app/Info.plist")
cat <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>TouchMac</title>
    <item>
      <title>TouchMac $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN</sparkle:minimumSystemVersion>
      <description><![CDATA[$(cat "$NOTES")]]></description>
      <enclosure url="$URL" type="application/octet-stream" $SIG />
    </item>
  </channel>
</rss>
XML
