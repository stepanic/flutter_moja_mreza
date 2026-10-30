#!/bin/bash
# Snimke zaslona za Chrome Web Store (1280×800) u ../build/web-store/.
# Popup je pravi popup.html s lažnim chrome.* (stub.js) i izmišljenim podacima.
set -e
cd "$(dirname "$0")/../.."
izlaz=../build/web-store; mkdir -p "$izlaz"
port=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])')
python3 -m http.server $port --bind 127.0.0.1 >/dev/null 2>&1 & srv=$!
trap 'kill $srv 2>/dev/null' EXIT
sleep 1
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
for s in mreza hepi-gotovo mreza-gotovo racun-gotovo drugo; do
  "$chrome" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --window-size=1280,800 --virtual-time-budget=3000 \
    --screenshot="$PWD/$izlaz/$s.png" "http://127.0.0.1:$port/tools/snimke/okvir.html?stanje=$s" 2>/dev/null
done
"$chrome" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
  --window-size=440,280 --virtual-time-budget=1000 \
  --screenshot="$PWD/$izlaz/plocica-440x280.png" "http://127.0.0.1:$port/tools/snimke/plocica.html" 2>/dev/null
ls -1 "$izlaz"
