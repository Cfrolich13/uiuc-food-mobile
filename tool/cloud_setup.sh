#!/usr/bin/env bash
# Setup script for Claude Code cloud sessions: installs the Flutter SDK so
# `flutter analyze` and `flutter test` can run before committing, and trusts the
# University's certificate root so tool/live_feed_check.dart reaches the live feed.
# Keep FLUTTER_VERSION in step with .github/workflows/build.yml.
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.7}"
FLUTTER_HOME="${FLUTTER_HOME:-/opt/flutter}"

# The container's CA store lacks emSign Root CA - G1, the root of the University
# feed's certificate (phones trust it), so Dart and tool/live_feed_check.dart fail
# TLS without it. This is Mozilla's copy (https://curl.se/ca/cacert.pem), SHA-256
# 40:F6:AF:03:46:A9:9A:A1:CD:1D:55:5A:4E:9C:CE:62:C7:F9:63:46:03:EE:40:66:15:83:3D:C8:C8:D0:03:67.
EMSIGN_CERT=/usr/local/share/ca-certificates/emsign-root-ca-g1.crt
if [ ! -f "$EMSIGN_CERT" ] && command -v update-ca-certificates >/dev/null; then
  cat > "$EMSIGN_CERT" <<'PEM'
-----BEGIN CERTIFICATE-----
MIIDlDCCAnygAwIBAgIKMfXkYgxsWO3W2DANBgkqhkiG9w0BAQsFADBnMQswCQYDVQQGEwJJTjET
MBEGA1UECxMKZW1TaWduIFBLSTElMCMGA1UEChMcZU11ZGhyYSBUZWNobm9sb2dpZXMgTGltaXRl
ZDEcMBoGA1UEAxMTZW1TaWduIFJvb3QgQ0EgLSBHMTAeFw0xODAyMTgxODMwMDBaFw00MzAyMTgx
ODMwMDBaMGcxCzAJBgNVBAYTAklOMRMwEQYDVQQLEwplbVNpZ24gUEtJMSUwIwYDVQQKExxlTXVk
aHJhIFRlY2hub2xvZ2llcyBMaW1pdGVkMRwwGgYDVQQDExNlbVNpZ24gUm9vdCBDQSAtIEcxMIIB
IjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAk0u76WaK7p1b1TST0Bsew+eeuGQzf2N4aLTN
LnF115sgxk0pvLZoYIr3IZpWNVrzdr3YzZr/k1ZLpVkGoZM0Kd0WNHVO8oG0x5ZOrRkVUkr+PHB1
cM2vK6sVmjM8qrOLqs1D/fXqcP/tzxE7lM5OMhbTI0Aqd7OvPAEsbO2ZLIvZTmmYsvePQbAyeGHW
DV/D+qJAkh1cF+ZwPjXnorfCYuKrpDhMtTk1b+oDafo6VGiFbdbyL0NVHpENDtjVaqSW0RM8LHhQ
6DqS0hdW5TUaQBw+jSztOd9C4INBdN+jzcKGYEho42kLVACL5HZpIQ15TjQIXhTCzLG3rdd8cIrH
hQIDAQABo0IwQDAdBgNVHQ4EFgQU++8Nhp6w492pufEhF38+/PB3KxowDgYDVR0PAQH/BAQDAgEG
MA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcNAQELBQADggEBAFn/8oz1h31xPaOfG1vR2vjTnGs2
vZupYeveFix0PZ7mddrXuqe8QhfnPZHr5X3dPpzxz5KsbEjMwiI/aTvFthUvozXGaCocV685743Q
NcMYDHsAVhzNixl03r4PEuDQqqE/AjSxcM6dGNYIAwlG7mDgfrbESQRRfXBgvKqy/3lyeqYdPV8q
+Mri/Tm3R7nrft8EI6/6nAYH6ftjk4BAtcZsCjEozgyfz7MjNYBBjWzEN3uBL4ChQEKF6dk4jeih
U80Bv2noWgbyRQuQ+q7hv53yrlc8pa6yVvSLZUDp/TGBLPQ5Cdjua6e0ph0VpZj3AYHYhX3zUVxx
iN66zB+Afko=
-----END CERTIFICATE-----
PEM
  update-ca-certificates >/dev/null
fi

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
