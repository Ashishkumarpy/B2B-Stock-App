import { useEffect, useMemo, useState } from 'react';
import { Outlet, Link, useNavigate } from 'react-router';
import { Menu, Search, User, ShoppingCart, X, ChevronRight, Mail, Phone, Award, Download } from 'lucide-react';
import { useCart } from '../../context/CartContext';
import { CartDrawer } from '../cart/CartDrawer';
import logo from '../../../imports/LOGO.png';
import { subscribeToProducts, type Product } from '../../../lib/productService';
import { slugifyCategoryName } from '../../../lib/category';

const DEFAULT_CATEGORIES = [
  { name: 'Bags', slug: 'bags', count: '150+ Products' },
  { name: 'Card Holders', slug: 'card-holders', count: '85+ Products' },
  { name: 'Electronics', slug: 'electronics', count: '120+ Products' },
  { name: 'Gift Sets & Combos', slug: 'gift-sets', count: '95+ Products' },
  { name: 'Diwali Catalogue', slug: 'diwali', count: '200+ Products' },
  { name: 'ID Cards', slug: 'id-cards', count: '50+ Products' },
  { name: 'Keychains & Badge Reels', slug: 'keychains', count: '75+ Products' },
  { name: 'Water Bottles', slug: 'water-bottles', count: '100+ Products' },
  { name: 'Mugs', slug: 'mugs', count: '110+ Products' },
  { name: 'Notebooks & Diaries', slug: 'notebooks', count: '130+ Products' },
];

export function Layout() {
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [searchOpen, setSearchOpen] = useState(false);
  const { totalQuantity, setIsDrawerOpen } = useCart();
  const [products, setProducts] = useState<Product[]>([]);
  const [searchQuery, setSearchQuery] = useState('');
  const navigate = useNavigate();

  useEffect(() => {
    // Live categories/counts: keep the sidebar in sync with the products table.
    const unsub = subscribeToProducts(setProducts);
    return () => unsub();
  }, []);

  const searchResults = useMemo(() => {
    if (!searchQuery.trim()) return [];
    const query = searchQuery.toLowerCase().trim();
    return products.filter(
      (p) =>
        p.name.toLowerCase().includes(query) ||
        p.code.toLowerCase().includes(query) ||
        (p.category && p.category.toLowerCase().includes(query)) ||
        (p.description && p.description.toLowerCase().includes(query))
    ).slice(0, 5);
  }, [searchQuery, products]);

  const handleSearchSubmit = (e?: React.FormEvent) => {
    e?.preventDefault();
    if (searchQuery.trim()) {
      navigate(`/products?search=${encodeURIComponent(searchQuery.trim())}`);
      setSearchOpen(false);
      setSearchQuery('');
    }
  };

  const productCategories = useMemo(() => {
    const counts = new Map<string, number>();
    for (const product of products) {
      if (product.stockStatus === 'out_of_stock') continue;
      const name = product.category?.trim();
      if (!name) continue;
      counts.set(name, (counts.get(name) ?? 0) + 1);
    }

    const categories = Array.from(counts.entries())
      .map(([name, count]) => ({ name, slug: slugifyCategoryName(name), count, countLabel: `${count} Products` }))
      .sort((a, b) => b.count - a.count || a.name.localeCompare(b.name))
      .map(({ count, countLabel, ...rest }) => ({ ...rest, count: countLabel }));

    return categories.length > 0 ? categories : DEFAULT_CATEGORIES;
  }, [products]);

  return (
    <div className="min-h-screen bg-white text-slate-900 flex flex-col">
      {/* Header (Powerpl-style): announcement + sticky nav */}
      <div className="fixed top-0 w-full z-50">
        <div className="bg-slate-900 text-white text-xs tracking-wide">
          <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-9 flex items-center justify-between">
            <span>Welcome! Free shipping on orders of ₹1500 and above</span>
            <div className="hidden sm:flex items-center gap-4 text-white/80">
              <span className="cursor-default hover:text-white transition-colors">Regional Distributors</span>
              <span className="cursor-default hover:text-white transition-colors">Become a Distributor</span>
            </div>
          </div>
        </div>

        <nav className="w-full bg-white/95 backdrop-blur-sm border-b border-slate-200">
          <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
            <div className="flex items-center justify-between h-20">
              {/* Left: Menu Icon */}
              <button
                onClick={() => setSidebarOpen(true)}
                className="flex items-center gap-2 hover:text-slate-600 transition-colors"
              >
                <Menu className="w-6 h-6" />
                <span className="hidden md:inline text-xs uppercase tracking-wider">Menu</span>
              </button>

              {/* Center: Logo */}
              <div className="absolute left-1/2 transform -translate-x-1/2">
                <Link to="/" className="flex items-center gap-3">
                  <img src={logo} alt="Xpress Gifting" className="h-10 w-10" />
                  <h1 className="text-xl md:text-2xl tracking-tight uppercase hidden sm:block">Xpress Gifting</h1>
                </Link>
              </div>

              {/* Right: Search, User, Cart */}
              <div className="flex items-center gap-4 md:gap-6">
                <button
                  onClick={() => setSearchOpen(!searchOpen)}
                  className="hover:text-slate-600 transition-colors"
                >
                  <Search className="w-5 h-5" />
                </button>
                <button className="hover:text-slate-600 transition-colors">
                  <User className="w-5 h-5" />
                </button>
                <button
                  className="hover:text-slate-600 transition-colors relative"
                  onClick={() => setIsDrawerOpen(true)}
                >
                  <ShoppingCart className="w-5 h-5" />
                  {totalQuantity > 0 && (
                    <span className="absolute -top-1 -right-1 w-4 h-4 bg-slate-900 text-white text-[10px] rounded-full flex items-center justify-center">
                      {totalQuantity}
                    </span>
                  )}
                </button>
              </div>
            </div>
          </div>

          {/* Search Bar */}
          {searchOpen && (
            <div className="border-t border-slate-200 bg-white relative z-50">
              <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4 relative">
                <form onSubmit={handleSearchSubmit} className="relative">
                  <input
                    type="text"
                    placeholder="SEARCH PRODUCTS..."
                    value={searchQuery}
                    onChange={(e) => setSearchQuery(e.target.value)}
                    className="w-full px-6 py-3 bg-white border border-slate-200 text-slate-900 placeholder-slate-400 focus:outline-none focus:border-slate-900 transition-colors uppercase tracking-wider text-sm pr-12"
                    autoFocus
                  />
                  <button type="submit" className="absolute right-4 top-1/2 transform -translate-y-1/2 text-slate-500 hover:text-slate-900 transition-colors cursor-pointer">
                    <Search className="w-5 h-5" />
                  </button>
                </form>

                {/* Instant Search Results Dropdown */}
                {searchResults.length > 0 && (
                  <div className="absolute left-4 right-4 sm:left-6 sm:right-6 lg:left-8 lg:right-8 mt-2 bg-white border border-slate-200 shadow-2xl rounded-md z-[100] max-h-96 overflow-y-auto divide-y divide-slate-100">
                    {searchResults.map((product) => (
                      <Link
                        key={product.id}
                        to={`/product/${product.id}`}
                        onClick={() => {
                          setSearchOpen(false);
                          setSearchQuery('');
                        }}
                        className="flex items-center gap-4 p-4 hover:bg-slate-50 transition-colors"
                      >
                        <div className="w-12 h-12 bg-slate-50 border border-slate-200 flex-shrink-0 flex items-center justify-center p-1">
                          <img
                            src={product.imageUrl || 'https://images.unsplash.com/photo-1561172472-4f2d94f35e87?w=100'}
                            alt={product.name}
                            className="max-w-full max-h-full object-contain"
                          />
                        </div>
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center gap-2 mb-0.5">
                            <span className="text-xs uppercase tracking-wider text-slate-500">{product.category}</span>
                            {product.stockStatus === 'out_of_stock' && (
                              <span className="text-[9px] bg-red-100 text-red-700 px-1 py-0.5 rounded uppercase font-medium">Out of Stock</span>
                            )}
                          </div>
                          <h4 className="text-sm font-medium text-slate-900 truncate uppercase">{product.name}</h4>
                          <div className="text-[10px] text-slate-400 uppercase tracking-widest">SKU: {product.code}</div>
                        </div>
                        <div className="text-sm font-semibold text-slate-950 pr-2">
                          ₹{product.price.toLocaleString()}
                        </div>
                      </Link>
                    ))}
                    <div className="p-3 text-center bg-slate-50">
                      <button
                        onClick={handleSearchSubmit}
                        className="text-xs uppercase tracking-widest text-slate-600 hover:text-slate-955 font-medium transition-colors cursor-pointer"
                      >
                        View all results
                      </button>
                    </div>
                  </div>
                )}
                {searchQuery.trim() !== '' && searchResults.length === 0 && (
                  <div className="absolute left-4 right-4 sm:left-6 sm:right-6 lg:left-8 lg:right-8 mt-2 bg-white border border-slate-200 shadow-xl rounded-md p-6 text-center text-sm text-slate-500 uppercase tracking-wider z-[100]">
                    No products found matching "{searchQuery}"
                  </div>
                )}
              </div>
            </div>
          )}
        </nav>
      </div>

      {/* Sidebar Menu */}
      <div
        className={`fixed inset-0 bg-slate-900/40 backdrop-blur-sm z-50 transition-opacity duration-300 ${
          sidebarOpen ? 'opacity-100' : 'opacity-0 pointer-events-none'
        }`}
        onClick={() => setSidebarOpen(false)}
      >
        <div
          className={`fixed left-0 top-0 h-full w-80 md:w-96 bg-white border-r border-slate-200 transform transition-transform duration-300 ${
            sidebarOpen ? 'translate-x-0' : '-translate-x-full'
          }`}
          onClick={(e) => e.stopPropagation()}
        >
          {/* Sidebar Header */}
          <div className="flex items-center justify-between p-6 border-b border-white/10">
            <h2 className="text-xl uppercase tracking-wider text-slate-900">Categories</h2>
            <button onClick={() => setSidebarOpen(false)} className="hover:text-slate-600 transition-colors">
              <X className="w-6 h-6" />
            </button>
          </div>

          {/* Sidebar Content */}
          <div className="overflow-y-auto h-[calc(100%-80px)]">
            <div className="p-6 space-y-2">
              {productCategories.map((category) => (
                <Link
                  key={category.name}
                  to={`/category/${category.slug}`}
                  onClick={() => setSidebarOpen(false)}
                  className="group flex items-center justify-between p-4 hover:bg-slate-50 border border-slate-200 hover:border-slate-300 transition-all"
                >
                  <div className="flex items-center gap-4">
                    <div>
                      <h3 className="text-sm uppercase tracking-wider mb-1 text-slate-900">{category.name}</h3>
                      <p className="text-xs text-slate-500 uppercase tracking-wider">{category.count}</p>
                    </div>
                  </div>
                  <ChevronRight className="w-5 h-5 text-slate-400 group-hover:text-slate-900 transition-colors" />
                </Link>
              ))}
            </div>

            {/* Sidebar Footer Links */}
            <div className="border-t border-slate-200 p-6">
              <div className="space-y-4">
                <Link to="/#why-us" onClick={() => setSidebarOpen(false)} className="flex items-center gap-3 text-sm uppercase tracking-wider hover:text-slate-600 transition-colors text-slate-800">
                  <Award className="w-4 h-4" />
                  About Us
                </Link>
                <Link to="/#contact" onClick={() => setSidebarOpen(false)} className="flex items-center gap-3 text-sm uppercase tracking-wider hover:text-slate-600 transition-colors text-slate-800">
                  <Mail className="w-4 h-4" />
                  Contact
                </Link>
                <a href="tel:+919876543210" className="flex items-center gap-3 text-sm uppercase tracking-wider hover:text-slate-600 transition-colors text-slate-800">
                  <Phone className="w-4 h-4" />
                  +91 98765 43210
                </a>
              </div>

              <Link
                to="/#contact"
                onClick={() => setSidebarOpen(false)}
                className="mt-6 block w-full px-6 py-3 bg-slate-900 text-white text-center hover:bg-slate-800 transition-colors text-sm uppercase tracking-wider"
              >
                Get Quote
              </Link>
            </div>
          </div>
        </div>
      </div>

      <CartDrawer />

      {/* Main Content Area */}
      <main className="flex-1">
        <Outlet />
      </main>

      {/* Footer */}
      <footer className="bg-white text-slate-900 border-t border-slate-200 py-16">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="grid md:grid-cols-4 gap-12 mb-16">
            {/* Company Info */}
            <div>
              <div className="flex items-center gap-3 mb-6">
                <img src={logo} alt="Xpress Gifting" className="h-12 w-12" />
                <h3 className="text-2xl tracking-tight uppercase">Xpress Gifting</h3>
              </div>
              <p className="text-sm text-slate-600 mb-6 uppercase tracking-wider leading-relaxed">
                Premium corporate gifting solutions for modern businesses
              </p>
              <div className="flex gap-3">
                <a href="#" className="w-10 h-10 border border-slate-200 flex items-center justify-center hover:bg-slate-900 hover:text-white transition-all">
                  <span className="text-xs uppercase">FB</span>
                </a>
                <a href="#" className="w-10 h-10 border border-slate-200 flex items-center justify-center hover:bg-slate-900 hover:text-white transition-all">
                  <span className="text-xs uppercase">IG</span>
                </a>
                <a href="#" className="w-10 h-10 border border-slate-200 flex items-center justify-center hover:bg-slate-900 hover:text-white transition-all">
                  <span className="text-xs uppercase">LI</span>
                </a>
              </div>
            </div>

            {/* Quick Links */}
            <div>
              <h4 className="mb-6 text-sm uppercase tracking-widest">Quick Links</h4>
              <ul className="space-y-3 text-sm text-slate-600">
                <li>
                  <Link to="/" className="hover:text-slate-900 transition-colors uppercase tracking-wider">
                    Home
                  </Link>
                </li>
                <li>
                  <Link to="/products" className="hover:text-slate-900 transition-colors uppercase tracking-wider">
                    Products
                  </Link>
                </li>
                <li>
                  <Link to="/#why-us" className="hover:text-slate-900 transition-colors uppercase tracking-wider">
                    About
                  </Link>
                </li>
                <li>
                  <Link to="/#contact" className="hover:text-slate-900 transition-colors uppercase tracking-wider">
                    Contact
                  </Link>
                </li>
              </ul>
            </div>

            {/* Product Categories */}
            <div>
              <h4 className="mb-6 text-sm uppercase tracking-widest">Categories</h4>
              <ul className="space-y-3 text-sm text-slate-600">
                {productCategories.slice(0, 5).map((cat) => (
                  <li key={cat.name}>
                    <Link
                      to={`/category/${cat.slug}`}
                      className="hover:text-slate-900 transition-colors uppercase tracking-wider"
                    >
                      {cat.name}
                    </Link>
                  </li>
                ))}
              </ul>
            </div>

            {/* Contact Info */}
            <div>
              <h4 className="mb-6 text-sm uppercase tracking-widest">Contact</h4>
              <ul className="space-y-4 text-sm text-slate-600">
                <li className="flex items-center gap-3">
                  <Mail className="w-4 h-4" />
                  <a href="mailto:info@xpressgifting.com" className="hover:text-slate-900 transition-colors uppercase tracking-wider">
                    info@xpressgifting.com
                  </a>
                </li>
                <li className="flex items-center gap-3">
                  <Phone className="w-4 h-4" />
                  <a href="tel:+919876543210" className="hover:text-slate-900 transition-colors uppercase tracking-wider">
                    +91 98765 43210
                  </a>
                </li>
              </ul>
              <Link
                to="/#contact"
                className="inline-flex items-center gap-2 mt-6 px-6 py-3 bg-slate-900 text-white hover:bg-slate-800 transition-colors text-xs uppercase tracking-widest"
              >
                <Download className="w-4 h-4" />
                Catalogue
              </Link>
            </div>
          </div>

          <div className="border-t border-slate-200 pt-8 flex flex-col md:flex-row justify-between items-center text-xs text-slate-500 uppercase tracking-widest">
            <p>&copy; 2026 Xpress Gifting. All Rights Reserved.</p>
            <div className="flex gap-6 mt-4 md:mt-0">
              <a href="#" className="hover:text-slate-900 transition-colors">
                Privacy Policy
              </a>
              <a href="#" className="hover:text-slate-900 transition-colors">
                Terms
              </a>
            </div>
          </div>
        </div>
      </footer>
    </div>
  );
}
