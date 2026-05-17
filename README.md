# B2B Stock Platform

A full-stack B2B inventory and ordering platform for wholesalers, distributors, and manufacturers. This repo uses Supabase as the shared backend for the storefront, admin dashboard, and Flutter mobile app.

## Apps

| App | Stack | Purpose |
|---|---|---|
| `client/` | React 18, Vite, Tailwind CSS, Supabase | Customer storefront and checkout |
| `admin/` | Next.js 16, TypeScript, Supabase | Internal dashboard for products, stock, orders, and workers |
| `mobile/` | Flutter, Riverpod, Supabase, Hive | Worker/admin mobile workflows and stock operations |
| `server/` | Node.js, Express, Supabase, Cloudinary | Single backend API (server-first) |
| `supabase/` | SQL | Database schema and backend setup |
| `shared/` | TypeScript | Shared cross-app types |

## Project Structure

```text
B2B Stock App/
|-- admin/
|-- client/
|-- docs/
|-- mobile/
|-- server/
|-- shared/
`-- supabase/
```

## Backend

- Main schema file: `supabase/schema.sql`
- Frontends talk directly to Supabase using client SDKs
- Product images are stored in Cloudinary

## Environment Setup

### Client

Create `client/.env.local`:

```env
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_ANON_KEY=your-anon-key
```

### Admin

Use `admin/.env.example` as the template for `admin/.env.local`:

```env
NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-anon-key
NEXT_PUBLIC_CLOUDINARY_CLOUD_NAME=your-cloud-name
NEXT_PUBLIC_CLOUDINARY_UPLOAD_PRESET=your-unsigned-preset-name
```

### Mobile

The Flutter app uses the backend server. On first launch, set the Server URL in-app:
`Settings → Server` (example: `http://192.168.0.6:8080`).

Auth is handled by the server (`POST /auth/login`). The server validates against Supabase Auth and reads the user profile from `public.users` (see `supabase/schema.sql`).

To make **Admin/Worker sign-in** work:
- Create the user in Supabase Auth (Dashboard → Authentication → Users).
- Ensure a matching row exists in `public.users` (the `on_auth_user_created` trigger in `supabase/schema.sql` can auto-create it).
- Set the user role in `public.users.role` to `admin` or `worker` (default is `worker`).

Product images picked from the phone are uploaded via the server (`POST /uploads/image`) and the returned URL is saved in `products.image_url`.

## Local Development

### Server

```bash
cd server
npm install
cp .env.example .env
npm run dev
```

### Client

```bash
cd client
npm install
npm run dev
```

### Admin

```bash
cd admin
npm install
npm run dev
```

### Mobile

```bash
cd mobile
flutter pub get
flutter run
```

## Mobile App Updates

The platform includes an automated in-app update notification system for mobile workers.

### How to trigger an update:

1.  **Update Server Config**: Open `server/src/routes/app.js`.
2.  **Modify Version Data**: Update the JSON response in the `/version` route:
    *   `latestVersion`: Increment this (e.g., from `1.0.0` to `1.0.1`).
    *   `downloadUrl`: Provide the direct link to your new APK (or store link).
    *   `isCritical`: Set to `true` to force workers to update before they can continue.
    *   `releaseNotes`: Add a brief summary of what has changed.
3.  **Automatic Detection**: The next time a worker opens the mobile app, they will be greeted with a modern update dialog.

> [!TIP]
> The app uses smart semantic versioning comparison (e.g., `1.1.0` > `1.0.9`), so you can easily manage patch, minor, and major releases.

## Notes

- `client/src/lib/productService.ts` contains the storefront product queries and realtime subscriptions.
- `admin/lib/supabase.ts` and `client/src/lib/supabase.ts` hold the web SDK clients.
- Firebase has been removed from the active app source and setup flow.
