# ⚡ Zentory API Gateway

The **Zentory API Gateway** is the central backend engine orchestrating the Zentory ecosystem. It provides cookie-based session authentication for web clients, JWT token validation for mobile applications, asset optimization pipelines (Cloudinary + Sharp), push notification dispatches (Firebase Admin FCM), and bulk catalog import automation.

---

## 🌟 Key Features

- **🔑 Unified Authentication:**
  - *Web (Storefront & Admin):* Secure HTTP-only cookies session lifecycle management.
  - *Mobile:* JSON Web Token (JWT) Bearer authorization headers validation.
- **🖼️ Asset Processing Pipeline:** Integrates **Multer** and **Sharp** to crop, resize, and optimize product photos locally before uploading them to the **Cloudinary CDN**.
- **🔔 Push Alerts Dispatcher:** Exposes Firebase Cloud Messaging (FCM) admin triggers to send real-time operational notifications to mobile workers.
- **🔄 Version Checks Endpoint:** Exposes the update version metrics needed for the Flutter In-App Update Delivery subsystem.
- **📂 Bulk Catalog Seeders:** Powerful import scripts that process local design files, upload images dynamically to category-specific folders on Cloudinary, and seed the product database in Supabase.

---

## ⚙️ Tech Stack & Dependencies

- **Platform:** Node.js (v18+, Native ESM)
- **Framework:** [Express](https://expressjs.com/)
- **Database Client:** [@supabase/supabase-js](https://supabase.com/docs/reference/javascript/introduction)
- **Asset Storage:** [Cloudinary Node SDK](https://cloudinary.com/documentation/node_integration)
- **Image Processing:** [Sharp](https://sharp.pixelplumbing.com/) & [Multer](https://github.com/expressjs/multer)
- **Push Notifications:** [Firebase Admin SDK (`firebase-admin`)](https://firebase.google.com/docs/admin/setup)
- **Authentication:** `jsonwebtoken` & `cookie-parser`

---

## 🚀 Getting Started

### 1. Prerequisites
Ensure Node.js (v18+) is installed.

### 2. Environment Configuration
Create a `.env` file in the `server/` directory:
```env
PORT=5000
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-supabase-service-role-key
JWT_SECRET=your-secure-jwt-secret-token

CLOUDINARY_CLOUD_NAME=your-cloudinary-cloud-name
CLOUDINARY_API_KEY=your-cloudinary-api-key
CLOUDINARY_API_SECRET=your-cloudinary-api-secret

# Firebase Credentials (for push notifications)
FIREBASE_PROJECT_ID=your-firebase-project-id
FIREBASE_CLIENT_EMAIL=your-firebase-admin-email@gserviceaccount.com
FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n..."
```

### 3. Installation
```bash
npm install
```

### 4. Run Development Server
```bash
npm run dev
```
The server will run on `http://localhost:5000` with hot-reloading active.

---

## 📡 API Endpoints Reference

### 🔐 Authentication
- `POST /auth/login` - Authenticates user. Sets HTTP-only session cookie for web, and returns client `{ token, user }`.
- `POST /auth/logout` - Revokes session and clears authentication cookies.
- `GET /auth/me` - Resolves active profile from cookies or Bearer Authorization token.

### 📦 Products (Catalog Management)
- `GET /products` - Fetches the product list (accessible to all authenticated users).
- `POST /products` - Creates a new product profile (Admin access only).
- `PUT /products/:id` - Updates an existing product details (Admin access only).
- `DELETE /products/:id` - Removes a product from the database (Admin access only).

### 🖼️ Asset Uploads
- `POST /uploads/image` - Multipart `file` upload. Optimizes via Sharp, uploads to Cloudinary, and returns `{ url, publicId }` (Admin access only).

### 📱 App Versioning
- `GET /app/version` - Returns JSON representation of the latest mobile version code, critical flag status, and release notes:
  ```json
  {
    "latestVersion": "1.3.1",
    "buildNumber": 7,
    "downloadUrl": "https://example.com/downloads/zentory.apk",
    "isCritical": false,
    "releaseNotes": "Bug fixes, updated colors synchronization, and improved logging details."
  }
  ```

---

## 📂 Bulk Catalog Imports

The server contains automated ingestion scripts inside `src/scripts/` to seed products and upload original images directly into Cloudinary CDN.

To run individual category imports:
```bash
npm run import:mugs
npm run import:electronics
npm run import:bags
npm run import:notebooks
```

To run the complete data ingestion sequence:
```bash
npm run import:all
```
*(Note: Ensure paths to asset folders and Supabase environment variables are configured correctly before running imports.)*
