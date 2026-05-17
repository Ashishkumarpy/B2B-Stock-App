# B2B Stock Mobile (Flutter)

Mobile app for **Admin/Worker** inventory workflows (products, stock operations, scanning, etc.).

## Prerequisites

- Flutter SDK (Dart `>=3.0.0 <4.0.0`)
- Android Studio / Xcode (for device/simulator)

## Setup

```bash
cd mobile
flutter pub get
```

## Run (development)

```bash
cd mobile
flutter run
```

## Backend server (required)

This app talks to the repo’s Node server (`server/`) for auth and APIs (examples: `POST /auth/login`, `GET /auth/me`).

Configure the server base URL (include port):

- **In-app (recommended):** `Settings -> Server` (example: `http://192.168.0.6:8080`)
- **CLI (legacy):** `flutter run --dart-define=SERVER_BASE_URL=http://192.168.0.6:8080`

Tip: if you run the server on your computer and test on a physical phone, use your computer’s LAN IP (not `localhost`).

## Troubleshooting

- “Missing server URL…”: set the URL in `Settings -> Server`.
- “Cannot reach server…”: confirm the phone and computer are on the same Wi‑Fi, and the server is running/reachable on port `8080`.
