# Zentory — Full-Stack B2B Inventory & Ordering Platform

**Zentory** is a premium, enterprise-grade full-stack B2B inventory, warehousing, and ordering ecosystem designed for wholesalers, distributors, and manufacturers. It orchestrates a customer-facing storefront, an internal admin dashboard, and a cross-platform mobile operations application, all unified under a single server-first architectural model.

---

## 🏗️ System Architecture

Zentory is built with a decoupled, modular design. Client applications communicate directly with **Supabase** for fast data reads and real-time subscriptions, while core write operations and administrative workflows are routed through a secure **Express API Gateway**.

```mermaid
graph TD
    %% Styling
    classDef client fill:#EFF6FF,stroke:#2563EB,stroke-width:2px,color:#0F172A;
    classDef api fill:#ECFDF5,stroke:#10B981,stroke-width:2px,color:#0F172A;
    classDef database fill:#FFFBEB,stroke:#F59E0B,stroke-width:2px,color:#0F172A;

    subgraph Clients [Client & User Layer]
        Storefront["🛍️ Customer Storefront<br/>(React + Vite Web App)"]
        AdminDashboard["📊 Admin Dashboard<br/>(Next.js Web App)"]
        MobileApp["📱 Operations Mobile App<br/>(Flutter iOS / Android)"]
    end

    subgraph Services [API & Services Layer]
        API["⚡ Node.js Express API<br/>(Express Gateway)"]
        Cloudinary["☁️ Cloudinary<br/>(Asset & Image CDN)"]
        FCM["🔔 Firebase FCM<br/>(Push Notification Service)"]
    end

    subgraph Core [Database & Auth Layer]
        Supabase["⚡ Supabase Platform<br/>(Postgres, Auth, Realtime)"]
    end

    %% Client Interactions
    Storefront -->|Auth & Realtime Subscriptions| Supabase
    AdminDashboard -->|Auth & Analytics| Supabase
    AdminDashboard -->|Asset Uploads & Core Actions| API
    MobileApp -->|Auth, Version Check & Operations| API

    %% API Connections
    API -->|Auth Sync & Database Sync| Supabase
    API -->|Direct Asset CDN Hosting| Cloudinary
    API -->|Dispatches Push Alerts| FCM

    %% Class Assign
    class Storefront,AdminDashboard,MobileApp client;
    class API,Cloudinary,FCM api;
    class Supabase database;
```

---

## 📦 App Components

The repository is organized into distinct, isolated modules:

| Path | Stack | Purpose |
| :--- | :--- | :--- |
| **[`client/`](file:///c:/Users/DELL/.antigravity/apps/B2B%20Stock%20App/client)** | React 18, Vite, Tailwind CSS, Supabase SDK | Customer storefront, product catalog, and ordering checkout. |
| **[`admin/`](file:///c:/Users/DELL/.antigravity/apps/B2B%20Stock%20App/admin)** | Next.js 16, TypeScript, Supabase client | Management dashboard for categories, stock levels, orders, and workers. |
| **[`mobile/`](file:///c:/Users/DELL/.antigravity/apps/B2B%20Stock%20App/mobile)** | Flutter, Riverpod, Hive, Supabase SDK | Worker/admin mobile workflows, barcode scanning, and inventory auditing. |
| **[`server/`](file:///c:/Users/DELL/.antigravity/apps/B2B%20Stock%20App/server)** | Node.js, Express, Supabase, Cloudinary | Production-ready central backend API controlling auth and heavy pipelines. |
| **[`supabase/`](file:///c:/Users/DELL/.antigravity/apps/B2B%20Stock%20App/supabase)** | PostgreSQL SQL Schemas | Core database structure, triggers, and row-level security (RLS) definitions. |
| **[`shared/`](file:///c:/Users/DELL/.antigravity/apps/B2B%20Stock%20App/shared)** | TypeScript | Shared cross-platform interface and data contract types. |

---

## ⚙️ Environment Configuration

Set up local `.env` configuration files for each client and backend application.

### 1. Storefront Client (`client/`)
Create a `client/.env` file:
```env
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_ANON_KEY=your-anon-key
VITE_API_URL=http://localhost:5000
```

### 2. Admin Panel (`admin/`)
Create an `admin/.env.local` file:
```env
NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-anon-key
NEXT_PUBLIC_API_URL=http://localhost:5000
```

### 3. Backend API Gateway (`server/`)
Create a `server/.env` file:
```env
PORT=5000
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-supabase-service-role-key
JWT_SECRET=your-secure-jwt-secret-token

CLOUDINARY_CLOUD_NAME=your-cloudinary-cloud-name
CLOUDINARY_API_KEY=your-cloudinary-api-key
CLOUDINARY_API_SECRET=your-cloudinary-api-secret

# Firebase Credentials (for push notifications)
FIREBASE_PROJECT_ID=b2b-stock-app-c9a38
FIREBASE_CLIENT_EMAIL=your-firebase-admin-email@gserviceaccount.com
FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n..."
```

### 4. Operations Mobile App (`mobile/`)
The Flutter application fetches configurations from the central API server. By default, it connects to:
- **Default Server API**: Configured dynamically under [app_constants.dart](file:///c:/Users/DELL/.antigravity/apps/B2B%20Stock%20App/mobile/lib/core/constants/app_constants.dart#L36).
- **Settings overrides**: You can manually change the API endpoint URL in the app under **Settings → Server Config** (e.g., `http://192.168.1.50:5000` for local network testing).

---

## 🚀 Local Development

Follow these steps to launch all Zentory systems concurrently on your machine.

### Step 1: Run the Backend API
```bash
cd server
npm install
npm run dev
```

### Step 2: Run the Customer Storefront
```bash
cd client
npm install
npm run dev
```

### Step 3: Run the Admin Dashboard
```bash
cd admin
npm install
npm run dev
```

### Step 4: Launch the Operations Mobile App
Make sure an Android Emulator or iOS Simulator is active.
```bash
cd mobile
flutter pub get
flutter run
```

---

## 🔄 Mobile In-App Updates System

Zentory features a built-in automated **In-App Update** delivery network. 

### 1. How it works:
- On app startup, the mobile application queries the `/app/version` endpoint of the Node.js Server.
- It parses the response and compares the version against its local version code (using high-fidelity semantic versioning logic).
- If an update is available, it displays a premium in-app update notification modal with release notes, offering immediate installation.

### 2. Custom User Control:
To ensure the app remains non-intrusive, workers can navigate to the **Settings** screen and toggle **In-App Update Alerts** on or off. 
- When disabled, automatic background version checks on startup are skipped.
- Manual checking via the **Check for Updates** button in Settings will always perform a direct live check regardless of the toggle state.

### 3. Server Configuration Structure:
Administrators can trigger global update prompts by editing the mock data handler inside the server directory at [`server/src/routes/app.js`](file:///c:/Users/DELL/.antigravity/apps/B2B%20Stock%20App/server/src/routes/app.js):
```javascript
res.json({
  latestVersion: '1.1.1',
  buildNumber: 5,
  downloadUrl: 'https://example.com/downloads/zentory-release.apk',
  isCritical: true, // Forces users to update to access dashboard
  releaseNotes: 'Performance optimization, beautiful new logo alignment, and persistent notification controls.'
});
```

---

## 📝 License
This project is private and proprietary. Copyright (c) 2026 Zentory. All rights reserved.
