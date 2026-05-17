# B2B Stock Server

Single backend for mobile/client/admin. Keeps credentials on the server and exposes:
- Auth: cookie session (web) + Bearer JWT (mobile)
- Products CRUD
- Cloudinary image upload (server-side)

## Setup

```bash
cd server
npm install
cp .env.example .env
npm run dev
```

Note: the server reads env vars from `server/.env` (same folder as `server/package.json`).

## Logs

- Development default: readable “pretty” logs (auto when `NODE_ENV!=production`)
- Force JSON logs: set `LOG_FORMAT=json`

## Auth

- `POST /auth/login` → sets httpOnly cookie and returns `{ token, user }`
- `POST /auth/logout` → clears cookie
- `GET /auth/me` → returns current user (cookie or Bearer token)

## Products

- `GET /products`
- `POST /products` (admin only)
- `PUT /products/:id` (admin only)
- `DELETE /products/:id` (admin only)

## Uploads

- `POST /uploads/image` (admin only) multipart `file` → returns `{ url, publicId }`

## Bulk Import (Catalog → Cloudinary + Supabase)

The import scripts under `server/src/scripts/`:
- Upload images to Cloudinary (organized by category folder)
- Upsert rows into Supabase `products` by `code`

Run all imports (uses the local `D:\\Editing\\Done\\...` paths embedded in scripts / JSON files):

```bash
cd server
npm run import:all
```
