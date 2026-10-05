#!/usr/bin/env bash
# Instalacija primjera na iPhone preko linka, unutar tailneta (ne javno).
#
# Tailscale iz App Storea na macOS-u ne smije posluživati direktorij (sandbox),
# pa direktorij poslužuje lokalni http.server, a `tailscale serve` proxy na njega.
# itms-services traži HTTPS s valjanim certifikatom; daje ga *.ts.net.
# iPhone mora biti u profilu teama 6SCK58757K (razvojni profil "*").
#
# Upotreba: tools/ios_ota.sh   (Ctrl+C gasi server i serve)
set -euo pipefail
cd "$(dirname "$0")/../example"

PORT=${PORT:-18765}
HOST=$(tailscale status --json | python3 -c "import json,sys; print(json.load(sys.stdin)['Self']['DNSName'].rstrip('.'))")
BASE="https://$HOST/mojamreza"
OUT=$(mktemp -d)

if lsof -iTCP:"$PORT" -sTCP:LISTEN >/dev/null; then
  echo "Port $PORT je zauzet, zadaj drugi: PORT=... $0" >&2
  exit 1
fi

cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>debugging</string>
<key>teamID</key><string>6SCK58757K</string>
<key>signingStyle</key><string>automatic</string>
</dict></plist>
PLIST
flutter build ipa --release --export-options-plist="$OUT/ExportOptions.plist"

WEB="$OUT/web"
mkdir -p "$WEB"
cp build/ios/ipa/*.ipa "$WEB/mojamreza.ipa"
VERZIJA=$(grep '^version:' pubspec.yaml | sed 's/version: *//; s/+.*//')

cat > "$WEB/manifest.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>items</key><array><dict>
<key>assets</key><array><dict><key>kind</key><string>software-package</string><key>url</key><string>$BASE/mojamreza.ipa</string></dict></array>
<key>metadata</key><dict>
<key>bundle-identifier</key><string>com.stepanic.mojamreza</string>
<key>bundle-version</key><string>$VERZIJA</string>
<key>kind</key><string>software</string>
<key>title</key><string>Moja mreža</string>
</dict></dict></array></dict></plist>
PLIST

cat > "$WEB/index.html" <<HTML
<!doctype html><html lang="hr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Moja mreža</title>
<style>body{font:17px -apple-system,sans-serif;margin:48px 24px;text-align:center}a{display:inline-block;padding:14px 24px;background:#0a7aff;color:#fff;border-radius:12px;text-decoration:none}</style></head>
<body><h2>Moja mreža $VERZIJA</h2><p><a href="itms-services://?action=download-manifest&amp;url=$BASE/manifest.plist">Instaliraj</a></p></body></html>
HTML

python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$WEB" &
HTTP_PID=$!
trap 'kill $HTTP_PID 2>/dev/null; tailscale serve --https=443 --set-path /mojamreza off >/dev/null 2>&1 || true' EXIT

echo "Na iPhoneu u Safariju otvori: $BASE/"
tailscale serve --https=443 --set-path /mojamreza "http://127.0.0.1:$PORT"
