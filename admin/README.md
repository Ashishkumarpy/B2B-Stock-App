# 📊 Zentory Admin Dashboard

The **Zentory Admin Dashboard** is a premium, enterprise-grade control panel designed for administrators, catalog managers, and operations dispatchers. Built with **Next.js 16**, **React 19**, and **Tailwind CSS v4**, it provides real-time oversight of inventory levels, workers, orders, and products.

---

## 🌟 Key Features

- **📊 Live Inventory & Auditing:** Subscribes to real-time database channels via Supabase to track product stock adjustments as they happen on the mobile floor.
- **🛍️ Order Management:** Monitor customer-facing orders submitted through the storefront, inspect transaction lists, and dispatch pending orders.
- **👥 Workers & Role Allocation:** Administer worker accounts, verify access, and manage user roles (Admin vs. Operator).
- **📂 Bulk Catalog Imports/Exports:** Import stock lists and export records to Excel using integrated **SheetJS (`xlsx`)** pipelines.
- **🔔 Notification Hub:** Dispatch push notifications to mobile workers using the server's Firebase Cloud Messaging integrations.

---

## ⚙️ Tech Stack & Dependencies

- **Framework:** [Next.js 16](https://nextjs.org/) (using the modern App Router)
- **Library:** [React 19](https://react.dev/)
- **Styling:** [Tailwind CSS v4](https://tailwindcss.com/)
- **Database Client:** [@supabase/supabase-js](https://supabase.com/docs/reference/javascript/introduction)
- **Utilities:** [xlsx](https://sheetjs.com/) (Excel processing), `firebase` (client notifications configuration)

---

## 🚀 Getting Started

### 1. Prerequisites
Ensure you have [Node.js](https://nodejs.org/) (v18+) installed.

### 2. Environment Configuration
Create a `.env.local` file in the `admin/` directory:
```env
NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-anon-key
NEXT_PUBLIC_API_URL=http://localhost:5000
```

### 3. Installation
Install the workspace dependencies:
```bash
npm install
```

### 4. Run Development Server
```bash
npm run dev
```
Open [http://localhost:3000](http://localhost:3000) to view the dashboard.

### 5. Production Build
To create a production-ready optimized bundle:
```bash
npm run build
npm run start
```

---

## 📂 Project Structure

- [`app/`](file:///c:/Users/DELL/.antigravity/apps/B2B%20Stock%20App/admin/app): Next.js App Router containing pages and routing definitions.
  - [`products/page.tsx`](file:///c:/Users/DELL/.antigravity/apps/B2B%20Stock%20App/admin/app/products/page.tsx): Product management panel.
- `components/`: Reusable dashboard widgets, tables, filters, and graphs.
- `lib/`: Helper functions, Supabase client initialization, and utility hooks.
- `public/`: Brand assets, fonts, and icons.
