$ErrorActionPreference = 'Stop'
flutter --version
flutter create --platforms=android .
python scripts/patch_android.py
flutter pub get
flutter build apk --debug
Write-Host "Debug APK: build/app/outputs/flutter-apk/app-debug.apk"
