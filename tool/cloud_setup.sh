#!/usr/bin/env bash
# Setup script for Claude Code cloud sessions: installs the Flutter SDK so
# `flutter analyze` and `flutter test` can run before committing.
# Keep FLUTTER_VERSION in step with .github/workflows/build.yml.
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.7}"
FLUTTER_HOME="${FLUTTER_HOME:-/opt/flutter}"

if [ ! -x "$FLUTTER_HOME/bin/flutter" ]; then
  archive="flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
  curl -fsSL --retry 4 -o "/tmp/$archive" \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/$archive"
  mkdir -p "$(dirname "$FLUTTER_HOME")"
  tar -xJf "/tmp/$archive" -C "$(dirname "$FLUTTER_HOME")"
  rm "/tmp/$archive"
fi

# The SDK is a git checkout owned by whoever extracted it.
git config --global --add safe.directory "$FLUTTER_HOME"
ln -sf "$FLUTTER_HOME/bin/flutter" /usr/local/bin/flutter
ln -sf "$FLUTTER_HOME/bin/dart" /usr/local/bin/dart

flutter config --no-analytics >/dev/null
flutter --disable-analytics >/dev/null 2>&1 || true
flutter precache --no-android --no-ios --no-web --no-linux --no-macos --no-windows >/dev/null 2>&1 || true
flutter --version

# Fetch packages when run from the repository checkout.
if [ -f pubspec.yaml ]; then flutter pub get; fi
