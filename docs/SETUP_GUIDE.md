# Setup guide

## Requirements

Flutter 3.44+ (Dart 3.12), Android SDK 34+, JDK 17.

## Run and test

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Visual check without a device (writes PNGs of the real screens):

```bash
SHOTS_DIR=/tmp/shots FLUTTER_ROOT=$(dirname $(dirname $(which flutter))) \
  flutter test test_tools/screenshots_test.dart
```

On a connected phone, the whole app end to end (menus, settings, a full match
to the winner, rematch, quit - about 6 minutes):

```bash
flutter test integration_test/full_app_test.dart -d <device-id>
```

Frame-time statistics in `adb logcat -s flutter` (lines starting `PERF`):

```bash
flutter build apk --release --dart-define=PERF_LOG=true
```

## Configuration

Copy `.env.example` to `.env` and build with
`--dart-define-from-file=.env`. All values are public identifiers; with
nothing set the app runs in demo mode.

| Key | Purpose |
|---|---|
| `API_BASE_URL` | Address of the PHP backend. Empty: offline only. |
| `CLOUDINARY_CLOUD_NAME` | Enables Cloudinary delivery URLs |
| `CLOUDINARY_UPLOAD_PRESET` | **Unsigned** preset; enables avatar upload |
| `CLOUDINARY_FOLDER` | Upload folder, default `billiard_poker` |

### Cloudinary (when the account is available)

1. Console -> Settings -> Upload -> add an **unsigned** upload preset; restrict
   it to images, set a size limit and the folder.
2. Put cloud name and preset name in `.env`.
3. Profile -> UPLOAD PHOTO becomes active; avatars are stored as
   `cld:<publicId>` and delivered through `CloudinaryService.imageUrl`.

The API secret is never needed in the app. Do not add it.

### Backend (online play)

See [backend/README.md](../backend/README.md) to install the PHP server, then
build the app with its address:

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://api.example.com
```

Local development: run `php -S 0.0.0.0:8080 -t public public/index.php` in
`backend/` and use `http://10.0.2.2:8080` from the Android emulator.

## Release builds

```bash
flutter build apk --release
flutter build appbundle --release
```

Release builds require `android/key.properties` (see `android/key.properties.example`).
Application ID: `com.pikope.piko`.

**Firebase push (optional):** In Firebase console, add Android app `com.pikope.piko`,
download `google-services.json` into `android/app/` (replace the placeholder).
On the server, set `FCM_SERVER_KEY` in `.env` for admin → Push delivery.
