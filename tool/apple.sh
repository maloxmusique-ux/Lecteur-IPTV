#!/bin/bash
# Compile et installe Canalix sur le Mac et/ou l'iPhone.
#   ./tool/apple.sh mac      -> /Applications/Canalix.app
#   ./tool/apple.sh iphone   -> installe sur l'iPhone branche (ou en Wi-Fi)
set -e
export PATH="/opt/homebrew/bin:$HOME/flutter/bin:$PATH"
cd "$(dirname "$0")/.."
DEFINES=()
[ -n "$LICENSE_API" ] && DEFINES+=(--dart-define=LICENSE_API="$LICENSE_API" --dart-define=LICENSE_KEY="$LICENSE_KEY")

git pull -q || true
flutter pub get >/dev/null

case "$1" in
  mac)
    flutter build macos --release "${DEFINES[@]}"
    rm -rf /Applications/Canalix.app
    cp -R build/macos/Build/Products/Release/Canalix.app /Applications/
    echo "OK : /Applications/Canalix.app"
    ;;
  iphone)
    # Signature automatique : equipe Apple deja dans le projet (LZMNRQX7Y9).
    DEVICE="${DEVICE:-$(flutter devices --machine | python3 -c 'import json,sys; d=[x for x in json.load(sys.stdin) if x.get("targetPlatform","").startswith("ios") and not x.get("emulator")]; print(d[0]["id"] if d else "")')}"
    [ -z "$DEVICE" ] && { echo "Aucun iPhone trouve : branche-le et deverrouille-le."; exit 1; }
    flutter build ios --release "${DEFINES[@]}"
    xcrun devicectl device install app --device "$DEVICE" build/ios/iphoneos/Runner.app
    echo "OK : installe sur l'iPhone"
    ;;
  *) echo "Utilisation : $0 mac|iphone"; exit 1 ;;
esac
