# 🛍️ Zentory Customer Storefront

The **Zentory Customer Storefront** is a premium, consumer-grade B2B web catalog and ordering application. Designed for speed, aesthetic excellence, and fluid interactivity, it allows corporate clients to browse the inventory catalog, configure customized logo placements on items, and submit bulk orders.

The UI design is based on the professional [Corporate Gifting Figma Specification](https://www.figma.com/design/yHZOP1PdUqu9lGjzfioeY9/Corporate-Gifting-Website-Design).

---

## 🌟 Key Features

- **🛍️ Product Catalog & Filtering:** Clean, lightning-fast product grid browsing with category segregation and search capabilities.
- **🎨 Logo customization preview:** Mockup-ready interactive catalog views that preview how corporate logos look on bulk items.
- **🛒 Dynamic Checkout Pipeline:** A premium cart experience, address details validation, and ordering workflow featuring Canvas Confetti celebrations on completion.
- **⚡ Real-time Stock Sync:** Connects directly to Supabase to verify product availability before checkout.
- **✨ Fluid Micro-animations:** Premium UI transitions powered by **Framer Motion** and **Tailwind CSS v4** animations.

---

## ⚙️ Tech Stack & Dependencies

- **Build Tool:** [Vite 6](https://vite.dev/)
- **Core Library:** [React 18](https://react.dev/)
- **Routing:** [React Router 7](https://reactrouter.com/)
- **Styling:** [Tailwind CSS v4](https://tailwindcss.com/) & [Material-UI (MUI)](https://mui.com/)
- **State & UI Primitives:** [Radix UI](https://www.radix-ui.com/)
- **Database Client:** [@supabase/supabase-js](https://supabase.com/docs/reference/javascript/introduction)
- **Animations:** [Framer Motion](https://www.framer.com/motion/)

---

## 🚀 Getting Started

### 1. Prerequisites
Ensure you have [Node.js](https://nodejs.org/) (v18+) installed.

### 2. Environment Configuration
Create a `.env` file in the `client/` directory:
```env
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_ANON_KEY=your-anon-key
VITE_API_URL=http://localhost:5000
```

### 3. Installation
Install the project dependencies:
```bash
npm install
```

### 4. Run Development Server
```bash
npm run dev
```
Open [http://localhost:5173](http://localhost:5173) in your browser.

### 5. Build for Production
```bash
npm run build
```

---

## 📂 Project Structure

- [`src/`](file:///c:/Users/DELL/.antigravity/apps/B2B%20Stock%20App/client/src): Main source directory.
  - `app/`: Routing setup, global configurations, and high-level page views.
    - [`pages/Products.tsx`](file:///c:/Users/DELL/.antigravity/apps/B2B%20Stock%20App/client/src/app/pages/Products.tsx): Catalog browsing interface.
    - [`pages/Checkout.tsx`](file:///c:/Users/DELL/.antigravity/apps/B2B%20Stock%20App/client/src/app/pages/Checkout.tsx): Shopping cart & checkout pipeline.
  - `components/`: UI widgets (buttons, input fields, header/footer navigation).
  - `styles/`: Core stylesheets (Tailwind imports and custom utility definitions).