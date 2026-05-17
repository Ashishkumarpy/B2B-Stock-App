import { useState } from 'react';
import { Link, Outlet, useLocation } from 'react-router';
import { Menu, X, ChevronDown, Download, Mail, Phone } from 'lucide-react';
import {
  ShoppingBag,
  CreditCard,
  Smartphone,
  Gift,
  Flame,
  IdCard,
  Key,
  Droplet,
  Coffee,
  BookOpen,
} from 'lucide-react';

const productCategories = [
  { name: 'Bags', icon: ShoppingBag, slug: 'bags' },
  { name: 'Card Holders', icon: CreditCard, slug: 'card-holders' },
  { name: 'Electronics', icon: Smartphone, slug: 'electronics' },
  { name: 'Gift Sets & Combos', icon: Gift, slug: 'gift-sets' },
  { name: 'Diwali Catalogue', icon: Flame, slug: 'diwali' },
  { name: 'ID Cards', icon: IdCard, slug: 'id-cards' },
  { name: 'Keychains & Badge Reels', icon: Key, slug: 'keychains' },
  { name: 'Water Bottles', icon: Droplet, slug: 'water-bottles' },
  { name: 'Mugs', icon: Coffee, slug: 'mugs' },
  { name: 'Notebooks & Diaries', icon: BookOpen, slug: 'notebooks' },
];

export default function Layout() {
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const [productsDropdownOpen, setProductsDropdownOpen] = useState(false);

  let location;
  try {
    location = useLocation();
  } catch (e) {
    location = { pathname: '/' };
  }

  return (
    <div className="min-h-screen bg-black text-white">
      {/* Navigation */}
      <nav className="fixed top-0 w-full bg-black/95 backdrop-blur-sm border-b border-white/10 z-50">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center h-20">
            {/* Logo */}
            <div className="flex-shrink-0">
              <Link to="/">
                <h1 className="text-3xl tracking-tighter uppercase">GIFTPRO</h1>
              </Link>
            </div>

            {/* Desktop Menu */}
            <div className="hidden md:flex items-center space-x-10">
              <Link
                to="/"
                className={`text-sm uppercase tracking-wider hover:text-gray-300 transition-colors ${
                  location.pathname === '/' ? 'text-white' : 'text-gray-400'
                }`}
              >
                Home
              </Link>
              <div
                className="relative"
                onMouseEnter={() => setProductsDropdownOpen(true)}
                onMouseLeave={() => setProductsDropdownOpen(false)}
              >
                <Link
                  to="/products"
                  className={`text-sm uppercase tracking-wider hover:text-gray-300 transition-colors flex items-center gap-1 ${
                    location.pathname.includes('/products') || location.pathname.includes('/category')
                      ? 'text-white'
                      : 'text-gray-400'
                  }`}
                >
                  Products <ChevronDown className="w-3 h-3" />
                </Link>
                {productsDropdownOpen && (
                  <div className="absolute top-full left-0 mt-4 w-64 bg-black border border-white/20 py-4">
                    {productCategories.map((cat) => (
                      <Link
                        key={cat.name}
                        to={`/category/${cat.slug}`}
                        className="flex items-center gap-3 px-6 py-3 text-sm uppercase tracking-wider hover:bg-white/5 transition-colors"
                      >
                        <cat.icon className="w-4 h-4" />
                        {cat.name}
                      </Link>
                    ))}
                  </div>
                )}
              </div>
              <Link
                to="/contact"
                className={`text-sm uppercase tracking-wider hover:text-gray-300 transition-colors ${
                  location.pathname === '/contact' ? 'text-white' : 'text-gray-400'
                }`}
              >
                Contact
              </Link>
              <Link
                to="/contact"
                className="px-8 py-3 bg-white text-black hover:bg-gray-200 transition-colors text-sm uppercase tracking-wider"
              >
                Get Quote
              </Link>
            </div>

            {/* Mobile Menu Button */}
            <button className="md:hidden" onClick={() => setMobileMenuOpen(!mobileMenuOpen)}>
              {mobileMenuOpen ? <X className="w-6 h-6" /> : <Menu className="w-6 h-6" />}
            </button>
          </div>
        </div>

        {/* Mobile Menu */}
        {mobileMenuOpen && (
          <div className="md:hidden bg-black border-t border-white/10">
            <div className="px-4 py-4 space-y-3">
              <Link
                to="/"
                className="block py-2 text-sm uppercase tracking-wider"
                onClick={() => setMobileMenuOpen(false)}
              >
                Home
              </Link>
              <Link
                to="/products"
                className="block py-2 text-sm uppercase tracking-wider"
                onClick={() => setMobileMenuOpen(false)}
              >
                Products
              </Link>
              <Link
                to="/contact"
                className="block py-2 text-sm uppercase tracking-wider"
                onClick={() => setMobileMenuOpen(false)}
              >
                Contact
              </Link>
              <Link
                to="/contact"
                className="block py-3 px-4 bg-white text-black text-center text-sm uppercase tracking-wider mt-4"
                onClick={() => setMobileMenuOpen(false)}
              >
                Get Quote
              </Link>
            </div>
          </div>
        )}
      </nav>

      {/* Category Navigation */}
      <div className="fixed top-20 left-0 right-0 bg-black/98 backdrop-blur-md border-b border-white/10 z-40">
        <div className="overflow-x-auto scrollbar-hide">
          <div className="flex items-center justify-start md:justify-center min-w-max px-6 md:px-4">
            {productCategories.map((category) => (
              <Link
                key={category.name}
                to={`/category/${category.slug}`}
                className="px-5 md:px-6 py-4 text-[11px] md:text-xs uppercase tracking-[0.15em] hover:text-gray-300 transition-colors whitespace-nowrap relative group"
              >
                {category.name}
                <span className="absolute bottom-0 left-0 w-0 h-[1px] bg-white group-hover:w-full transition-all duration-300"></span>
              </Link>
            ))}
          </div>
        </div>
      </div>

      {/* Main Content */}
      <main>
        <Outlet />
      </main>

      {/* Footer */}
      <footer className="bg-black text-white border-t border-white/10 py-16">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="grid md:grid-cols-4 gap-12 mb-16">
            {/* Company Info */}
            <div>
              <h3 className="text-3xl tracking-tighter mb-6 uppercase">GIFTPRO</h3>
              <p className="text-sm text-gray-400 mb-6 uppercase tracking-wider leading-relaxed">
                Premium corporate gifting solutions for modern businesses
              </p>
              <div className="flex gap-3">
                <a
                  href="#"
                  className="w-10 h-10 border border-white/20 flex items-center justify-center hover:bg-white hover:text-black transition-all"
                >
                  <span className="text-xs uppercase">FB</span>
                </a>
                <a
                  href="#"
                  className="w-10 h-10 border border-white/20 flex items-center justify-center hover:bg-white hover:text-black transition-all"
                >
                  <span className="text-xs uppercase">IG</span>
                </a>
                <a
                  href="#"
                  className="w-10 h-10 border border-white/20 flex items-center justify-center hover:bg-white hover:text-black transition-all"
                >
                  <span className="text-xs uppercase">LI</span>
                </a>
              </div>
            </div>

            {/* Quick Links */}
            <div>
              <h4 className="mb-6 text-sm uppercase tracking-widest">Quick Links</h4>
              <ul className="space-y-3 text-sm text-gray-400">
                <li>
                  <Link to="/" className="hover:text-white transition-colors uppercase tracking-wider">
                    Home
                  </Link>
                </li>
                <li>
                  <Link
                    to="/products"
                    className="hover:text-white transition-colors uppercase tracking-wider"
                  >
                    Products
                  </Link>
                </li>
                <li>
                  <Link
                    to="/contact"
                    className="hover:text-white transition-colors uppercase tracking-wider"
                  >
                    Contact
                  </Link>
                </li>
              </ul>
            </div>

            {/* Product Categories */}
            <div>
              <h4 className="mb-6 text-sm uppercase tracking-widest">Categories</h4>
              <ul className="space-y-3 text-sm text-gray-400">
                {productCategories.slice(0, 5).map((cat) => (
                  <li key={cat.name}>
                    <Link
                      to={`/category/${cat.slug}`}
                      className="hover:text-white transition-colors uppercase tracking-wider"
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
              <ul className="space-y-4 text-sm text-gray-400">
                <li className="flex items-center gap-3">
                  <Mail className="w-4 h-4" />
                  <a
                    href="mailto:info@giftpro.com"
                    className="hover:text-white transition-colors uppercase tracking-wider"
                  >
                    info@giftpro.com
                  </a>
                </li>
                <li className="flex items-center gap-3">
                  <Phone className="w-4 h-4" />
                  <a
                    href="tel:+919876543210"
                    className="hover:text-white transition-colors uppercase tracking-wider"
                  >
                    +91 98765 43210
                  </a>
                </li>
              </ul>
              <a
                href="#catalogue"
                className="inline-flex items-center gap-2 mt-6 px-6 py-3 bg-white text-black hover:bg-gray-200 transition-colors text-xs uppercase tracking-widest"
              >
                <Download className="w-4 h-4" />
                Catalogue
              </a>
            </div>
          </div>

          <div className="border-t border-white/10 pt-8 flex flex-col md:flex-row justify-between items-center text-xs text-gray-500 uppercase tracking-widest">
            <p>&copy; 2026 GiftPro. All Rights Reserved.</p>
            <div className="flex gap-6 mt-4 md:mt-0">
              <a href="#" className="hover:text-white transition-colors">
                Privacy Policy
              </a>
              <a href="#" className="hover:text-white transition-colors">
                Terms
              </a>
            </div>
          </div>
        </div>
      </footer>
    </div>
  );
}
