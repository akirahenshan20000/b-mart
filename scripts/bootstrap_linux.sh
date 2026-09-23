#!/usr/bin/env bash
set -euo pipefail
flutter --version
flutter create --platforms=android .
python3 scripts/patch_android.py
flutter pub get
flutter build apk --debug
echo "Debug APK: build/app/outputs/flutter-apk/app-debug.apk"
