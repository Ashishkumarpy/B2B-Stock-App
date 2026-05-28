# 📱 Zentory Operations Mobile App

The **Zentory Operations Mobile App** is a premium, cross-platform Flutter application designed for warehouse operators, drivers, and stock auditors. It enables real-time inventory adjustments, barcode scanning, offline operations logging, and automated updates.

---

## 🌟 Key Features

- **🔍 Barcode & QR Scanner:** Instantly scan products to view stock details, location, and metadata, using the device camera via **`mobile_scanner`**.
- **🔄 Live & Offline Transactions:** Log stock in/out operations (transactions) with support for offline queueing via local **Hive** caching.
- **📊 Real-time Auditing Dashboard:** Visual stock analytics, category distributions, and activity feeds powered by **`fl_chart`**.
- **🔔 Push Alerts:** Stay notified of urgent order dispatches and stock warnings via Firebase Cloud Messaging (FCM).
- **🚀 Automated In-App Updates:** Automatically queries the central backend version API on startup, prompting the worker to update when a new APK or build is available.
- **⚙️ Settings Override:** Configure base server configurations dynamically in-app (e.g., custom local IP endpoints for developers) and toggle automated update checks.

---

## ⚙️ Tech Stack & Dependencies

- **Framework:** Flutter SDK (Dart `>=3.0.0 <4.0.0`)
- **State Management:** [Riverpod (`flutter_riverpod`)](https://riverpod.dev/) with code generation via `riverpod_annotation`
- **Database Client:** [Supabase Flutter SDK (`supabase_flutter`)](https://supabase.com/docs/reference/flutter/introduction)
- **Local Storage:** [Hive Database (`hive_flutter`)](https://docs.hivedb.dev/)
- **Navigation:** [GoRouter (`go_router`)](https://pub.dev/packages/go_router)
- **Notifications:** [Firebase Messaging (`firebase_messaging`)](https://pub.dev/packages/firebase_messaging) & `flutter_local_notifications`
- **Visual Utilities:** `google_fonts`, `fl_chart`, `cached_network_image`, and `flutter_staggered_animations`

---

## 🚀 Getting Started

### 1. Prerequisites
- [Flutter SDK installed](https://docs.flutter.dev/get-started/install) (Dart SDK `>=3.0.0 <4.0.0`)
- Android Studio / Xcode configured (with emulator/simulator or physical device)

### 2. Dependency Resolution
Fetch all dependencies:
```bash
flutter pub get
```

### 3. Generate Code
Build generated code files (for Riverpod annotations & models):
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

### 4. Run Development Build
```bash
flutter run
```

---

## 🔗 Server Configuration & Networking

The mobile application communicates with the Node.js API Gateway (`server/`) to verify auth status, download configurations, and check versions.

- **Dynamic Server Address:** Go to **Settings -> Server Config** in the app to configure the IP address and port of your local dev server (e.g., `http://192.168.1.50:5000` or `http://10.0.2.2:5000` for Android emulator).
- **Update Checks Toggle:** In the **Settings** menu, workers can toggle **In-App Update Alerts** on or off. Disabling it skips background version queries on startup, but manual checks remain active.

---

## 📂 Project Structure

- [`lib/`](file:///c:/Users/DELL/.antigravity/apps/B2B Stock App/mobile/lib): Main Dart codebase.
  - `core/`: Navigation hooks, themes, client services, and Constants ([app_constants.dart](file:///c:/Users/DELL/.antigravity/apps/B2B%20Stock%20App/mobile/lib/core/constants/app_constants.dart)).
  - `domain/`: Business entities and validation interfaces ([transaction.dart](file:///c:/Users/DELL/.antigravity/apps/B2B%20Stock%20App/mobile/lib/domain/entities/transaction.dart)).
  - `data/`: Supabase repositories, Hive database service layers, and local models.
  - `presentation/`: Riverpod controllers, settings panels, scanning screens, and dashboard views.
- `assets/`: App icons, padded launcher logo ([Logo_padded.png](file:///c:/Users/DELL/.antigravity/apps/B2B%20Stock%20App/mobile/assets/images/Logo_padded.png)), and brand graphics.
