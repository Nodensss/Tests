#!/usr/bin/env bash
set -euo pipefail

FLUTTER_CHANNEL="${FLUTTER_CHANNEL:-stable}"
FLUTTER_DIR="$HOME/flutter"

if command -v flutter >/dev/null 2>&1; then
  echo "Flutter already available."
else
  echo "Installing Flutter (${FLUTTER_CHANNEL})..."
  rm -rf "$FLUTTER_DIR"
  git clone \
    --depth 1 \
    --branch "$FLUTTER_CHANNEL" \
    https://github.com/flutter/flutter.git \
    "$FLUTTER_DIR"
fi

if [ -d "$FLUTTER_DIR/bin" ]; then
  export PATH="$FLUTTER_DIR/bin:$PATH"
fi

flutter --version
flutter config --enable-web
flutter pub get
flutter build web --release --pwa-strategy=none
