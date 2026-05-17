# B2B Stock Platform - Architecture

## System Architecture

- `client/`: customer storefront powered by React, Vite, and Supabase.
- `admin/`: internal dashboard powered by Next.js and Supabase.
- `mobile/`: Flutter app using `supabase_flutter` plus Hive for local caching.
- `supabase/`: database schema, policies, and backend setup.
- `shared/`: shared domain types and cross-app models.

## Core Data Model

| Table | Description | Main Writers |
|---|---|---|
| `products` | Product catalog and stock metadata | Admin |
| `transactions` | Stock in/out activity | Mobile workers, Admin |
| `orders` | Customer orders from the storefront | Client |
| `users` | User profiles and roles | Admin / Auth sync |
| `workers` | Worker records and dashboard data | Admin |

## System Flow

1. Admin manages products and workers from the dashboard.
2. Client storefront reads product data from Supabase and submits orders.
3. Mobile workers create stock transactions through the Flutter app.
4. Supabase persists shared operational data for all apps.
5. Admin dashboards subscribe to live updates for inventory, orders, and workers.
