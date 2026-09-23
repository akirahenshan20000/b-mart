# BersolekMart Mobile — Flutter 1 APK

Single Android APK with role-based UI:

- `konsumen` / `customer` → shopping/customer UI
- `driver` → driver UI + location guard
- admin/operator/merchant are rejected from the mobile app

## Current phase

This project is intentionally scoped as the mobile client. The existing CodeIgniter backend remains authoritative.

### Implemented in this MVP

- API login → Bearer token issued by the existing backend
- Secure token storage
- `/api/v1/me` session validation
- Role routing
- Customer product list
- Customer order list
- Driver job list
- Driver location guard using Android location data
- Android mock-location detection exposed by `geolocator` (`Position.isMocked`)
- Location sync to existing `/api/v1/driver/location`
- Local movement-anomaly flag for very large jumps
- Configurable API base URL on the login screen

### Intentionally not implemented yet

- cart/checkout/payment API flows (existing backend API contract still needs these mobile endpoints)
- driver job status commands (the current backend endpoint is still `501 NOT_IMPLEMENTED`)
- server-side geofence / impossible-speed enforcement
- Play Integrity server verification

Those are separate phases so the current production business flow is not rewritten.

## Local API URL

Your XAMPP project is:

`http://localhost/bersolekmart/`

The Android Emulator does **not** use the PC's `localhost`. Default debug API URL is:

`http://10.0.2.2/bersolekmart/api/v1`

For a real phone, replace the base URL with the PC's LAN IP, for example:

`http://192.168.1.10/bersolekmart/api/v1`

The API server must be reachable from the device and Apache must allow that host/IP. CORS is not the limiting factor for a native Android HTTP client.

## Build a debug APK without installing Flutter locally

The repository includes `.github/workflows/build-debug-apk.yml`. GitHub Actions installs Flutter + Android tooling, creates the Android platform files, applies the local Android settings, runs `flutter analyze`, and builds the debug APK.

Use **Actions → Build BersolekMart Debug APK → Run workflow** in GitHub. The finished artifact is named:

`bersolekmart-debug-apk`

See `GITHUB_BUILD.md` for the exact steps.

For local Flutter development, the project can still be created with:

```bash
flutter create --platforms=android --project-name=bersolek_mart_mobile .
python scripts/patch_android.py
flutter pub get
flutter build apk --debug
```

APK output:

`build/app/outputs/flutter-apk/app-debug.apk`

## Android permissions

The Android app needs location permission. If you later enable background/foreground-service tracking, add the permissions required by the chosen location strategy. The current Flutter client keeps location tracking focused on the driver app flow.

## Anti-mock note

The client currently treats `Position.isMocked == true` as suspicious and does not send that location to the existing location endpoint. This is a **client-side detection layer**, not the final security boundary. Production enforcement should also validate evidence on the server and later use Play Integrity.
