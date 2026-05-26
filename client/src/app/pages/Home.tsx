import { useEffect, useMemo, useState } from 'react';
import Slider from 'react-slick';
import { motion } from 'motion/react';
import { Link } from 'react-router';
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
  CheckCircle,
  Award,
  Truck,
  HeadphonesIcon,
  ArrowRight,
} from 'lucide-react';
import 'slick-carousel/slick/slick.css';
import 'slick-carousel/slick/slick-theme.css';
import { subscribeToProducts, type Product } from '../../lib/productService';
import { slugifyCategoryName } from '../../lib/category';

const carouselSlides = [
  [
    {
      category: 'NEW ARRIVALS',
      title: 'PREMIUM BAGS',
      image: 'https://images.unsplash.com/photo-1529400971008-f566de0e6dfc?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&q=80&w=800',
    },
    {
      category: 'TRENDING',
      title: 'CARD HOLDERS',
      image: 'https://images.unsplash.com/photo-1770844063638-19e37f8c42eb?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&q=80&w=800',
    },
    {
      category: 'TECH',
      title: 'ELECTRONICS',
      image: 'https://images.unsplash.com/photo-1717295248494-937c3a5655b1?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&q=80&w=800',
    },
  ],
  [
    {
      category: 'BESTSELLERS',
      title: 'GIFT COMBOS',
      image: 'https://images.unsplash.com/photo-1763034179057-acad3a072568?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&q=80&w=800',
    },
    {
      category: 'FESTIVE',
      title: 'DIWALI SPECIAL',
      image: 'https://images.unsplash.com/photo-1699860807907-d14a60827a25?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&q=80&w=800',
    },
    {
      category: 'PREMIUM',
      title: 'WATER BOTTLES',
      image: 'https://images.unsplash.com/photo-1602143407151-7111542de6e8?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&q=80&w=800',
    },
  ],
  [
    {
      category: 'ESSENTIALS',
      title: 'NOTEBOOKS',
      image: 'https://images.unsplash.com/photo-1561172472-4f2d94f35e87?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&q=80&w=800',
    },
    {
      category: 'OFFICE',
      title: 'DESK ACCESSORIES',
      image: 'https://images.unsplash.com/photo-1565530623098-9f74c84d7f71?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&q=80&w=800',
    },
    {
      category: 'EXECUTIVE',
      title: 'PREMIUM SETS',
      image: 'https://images.unsplash.com/photo-1764264828455-10a4e9c3a991?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&q=80&w=800',
    },
  ],
];

const DEFAULT_CATEGORIES = [
  { name: 'Bags', icon: ShoppingBag, slug: 'bags', count: '150+ Products' },
  { name: 'Card Holders', icon: CreditCard, slug: 'card-holders', count: '85+ Products' },
  { name: 'Electronics', icon: Smartphone, slug: 'electronics', count: '120+ Products' },
  { name: 'Gift Sets & Combos', icon: Gift, slug: 'gift-sets', count: '95+ Products' },
  { name: 'Diwali Catalogue', icon: Flame, slug: 'diwali', count: '200+ Products' },
  { name: 'ID Cards', icon: IdCard, slug: 'id-cards', count: '50+ Products' },
  { name: 'Keychains & Badge Reels', icon: Key, slug: 'keychains', count: '75+ Products' },
  { name: 'Water Bottles', icon: Droplet, slug: 'water-bottles', count: '100+ Products' },
  { name: 'Mugs', icon: Coffee, slug: 'mugs', count: '110+ Products' },
  { name: 'Notebooks & Diaries', icon: BookOpen, slug: 'notebooks', count: '130+ Products' },
];

const ICON_BY_SLUG = {
  bags: ShoppingBag,
  'card-holders': CreditCard,
  electronics: Smartphone,
  'gift-sets': Gift,
  diwali: Flame,
  'id-cards': IdCard,
  keychains: Key,
  'water-bottles': Droplet,
  mugs: Coffee,
  notebooks: BookOpen,
} as const;

const whyChooseUs = [
  { icon: Award, title: 'Bulk Pricing Advantage', desc: 'Competitive rates for large orders' },
  { icon: Gift, title: 'Custom Branding', desc: 'Logo printing & personalization' },
  { icon: Truck, title: 'Fast Delivery', desc: 'Pan-India shipping network' },
  { icon: CheckCircle, title: 'Quality Assurance', desc: 'Premium products guaranteed' },
  { icon: HeadphonesIcon, title: 'Dedicated Support', desc: 'Account manager for your needs' },
];

export default function Home() {
  const [products, setProducts] = useState<Product[]>([]);

  useEffect(() => {
    // Populate the "Shop by Category" section from realtime product data (not hardcoded counts).
    const unsub = subscribeToProducts(setProducts);
    return () => unsub();
  }, []);

  const productCategories = useMemo(() => {
    const counts = new Map<string, number>();
    for (const product of products) {
      if (product.stockStatus === 'out_of_stock') continue;
      const name = product.category?.trim();
      if (!name) continue;
      counts.set(name, (counts.get(name) ?? 0) + 1);
    }

    const categories = Array.from(counts.entries())
      .map(([name, count]) => {
        const slug = slugifyCategoryName(name);
        const icon = (ICON_BY_SLUG as Record<string, typeof Gift>)[slug] ?? Gift;
        return { name, slug, icon, count: `${count} Products` };
      })
      .sort((a, b) => a.name.localeCompare(b.name));

    return categories.length > 0 ? categories : DEFAULT_CATEGORIES;
  }, [products]);

  const inStockProducts = useMemo(() => {
    return products.filter((p) => p.stockStatus !== 'out_of_stock');
  }, [products]);

  const carouselSettings = {
    dots: true,
    infinite: true,
    speed: 1200,
    slidesToShow: 1,
    slidesToScroll: 1,
    autoplay: true,
    autoplaySpeed: 4500,
    fade: true,
    cssEase: 'cubic-bezier(0.87, 0, 0.13, 1)',
    pauseOnHover: false,
  };

  return (
    <>
      {/* Hero Section with Carousel */}
      <section id="home" className="pt-32 relative overflow-hidden bg-black">
        <Slider {...carouselSettings}>
          {carouselSlides.map((slideGroup, groupIndex) => (
            <div key={groupIndex} className="relative">
              <div className="relative h-[75vh] md:h-[85vh]">
                <div className="grid grid-cols-1 md:grid-cols-3 h-full gap-1">
                  {slideGroup.map((slide, slideIndex) => (
                    <motion.div
                      key={slideIndex}
                      className="relative group overflow-hidden cursor-pointer"
                      initial={{ opacity: 0, scale: 1.1 }}
                      animate={{ opacity: 1, scale: 1 }}
                      transition={{ duration: 1.5, delay: slideIndex * 0.1 }}
                    >
                      {/* Image with Parallax */}
                      <motion.div
                        className="absolute inset-0"
                        whileHover={{ scale: 1.05 }}
                        transition={{ duration: 0.6 }}
                      >
                        <div
                          className="absolute inset-0 bg-cover bg-center"
                          style={{ backgroundImage: `url(${slide.image})` }}
                        />
                        <div className="absolute inset-0 bg-gradient-to-b from-black/40 via-transparent to-black/80 group-hover:from-black/50 group-hover:to-black/90 transition-all duration-500" />
                      </motion.div>

                      {/* Text Overlay */}
                      <div className="relative z-10 h-full flex flex-col justify-end p-6 md:p-8">
                        <motion.div
                          initial={{ opacity: 0, y: 20 }}
                          animate={{ opacity: 1, y: 0 }}
                          transition={{ delay: 0.6 + slideIndex * 0.1, duration: 0.8 }}
                        >
                          <div className="text-[10px] md:text-xs tracking-[0.2em] mb-3 uppercase text-gray-300">
                            {slide.category}
                          </div>
                          <h2 className="text-3xl md:text-4xl lg:text-5xl tracking-tighter uppercase leading-none text-white mb-4 group-hover:text-gray-100 transition-colors">
                            {slide.title}
                          </h2>
                          <div className="w-12 h-[1px] bg-white opacity-0 group-hover:opacity-100 group-hover:w-20 transition-all duration-500"></div>
                        </motion.div>
                      </div>
                    </motion.div>
                  ))}
                </div>
              </div>
            </div>
          ))}
        </Slider>

        {/* CTA Section Below Carousel */}
        <div className="py-12 text-center">
          <div className="flex flex-wrap justify-center gap-4">
            <Link
              to="/products"
              className="group px-12 py-4 bg-white text-black hover:bg-gray-200 transition-all duration-300 uppercase tracking-wider text-sm flex items-center gap-2"
            >
              Explore All
              <ArrowRight className="w-4 h-4 group-hover:translate-x-1 transition-transform" />
            </Link>
            <a
              href="#contact"
              className="px-12 py-4 bg-transparent text-white border border-white hover:bg-white hover:text-black transition-all duration-300 uppercase tracking-wider text-sm"
            >
              Bulk Orders
            </a>
          </div>
        </div>
      </section>

      {/* Product Categories Grid */}
      <section id="categories" className="py-24 bg-white">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="mb-20">
            <h2 className="text-5xl md:text-7xl tracking-tighter uppercase mb-4 text-slate-900">CATEGORIES</h2>
            <p className="text-lg text-slate-600 uppercase tracking-wider">
              Discover premium corporate gifting
            </p>
          </div>

          <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-5 gap-4">
            {productCategories.map((category, index) => (
              <Link
                key={category.name}
                to={`/category/${category.slug}`}
              >
                <motion.div
                  className="group relative bg-white hover:bg-slate-50 border border-slate-200 hover:border-slate-300 p-8 transition-all duration-300 overflow-hidden cursor-pointer h-full"
                  initial={{ opacity: 0, y: 20 }}
                  whileInView={{ opacity: 1, y: 0 }}
                  viewport={{ once: true }}
                  transition={{ delay: index * 0.05 }}
                >
                  <div className="relative z-10 flex flex-col items-center text-center gap-4 h-full justify-center">
                    <category.icon className="w-10 h-10 text-slate-900 group-hover:scale-110 transition-transform duration-300" />
                    <h3 className="text-sm uppercase tracking-wider text-slate-900">
                      {category.name}
                    </h3>
                    <ArrowRight className="w-4 h-4 text-slate-900 opacity-0 group-hover:opacity-100 transition-opacity mt-auto" />
                  </div>
                </motion.div>
              </Link>
            ))}
          </div>
        </div>
      </section>

      {/* New Arrivals */}
      <section className="py-24 bg-white">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="mb-20">
            <h2 className="text-5xl md:text-7xl text-slate-900 tracking-tighter uppercase mb-4">NEW ARRIVALS</h2>
            <p className="text-lg text-slate-600 uppercase tracking-wider">Fresh drops from the catalog</p>
          </div>

          <div className="mb-12 flex items-end justify-between gap-6">
            <div />
            <Link
              to="/products"
              className="hidden sm:inline-flex items-center gap-2 text-sm uppercase tracking-widest text-slate-700 hover:text-slate-900"
            >
              View all <ArrowRight className="w-4 h-4" />
            </Link>
          </div>

          {inStockProducts.length === 0 ? (
            <div className="text-slate-600 uppercase tracking-wider text-sm">No products yet.</div>
          ) : (
            <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-6">
              {inStockProducts.slice(0, 8).map((product, index) => (
                <Link key={product.id} to={`/product/${product.id}`}>
                  <motion.div
                    className="group cursor-pointer"
                    initial={{ opacity: 0, y: 20 }}
                    whileInView={{ opacity: 1, y: 0 }}
                    viewport={{ once: true }}
                    transition={{ delay: index * 0.03 }}
                  >
                    <div className="aspect-square overflow-hidden bg-slate-50 border border-slate-200 mb-4 relative">
                      <img
                        src={product.imageUrl || 'https://images.unsplash.com/photo-1561172472-4f2d94f35e87?w=600'}
                        alt={product.name}
                        className="w-full h-full object-contain p-4 group-hover:scale-105 transition-transform duration-500"
                      />
                      {product.stockStatus === 'out_of_stock' && (
                        <div className="absolute inset-0 bg-slate-900/40 flex items-center justify-center">
                          <span className="text-xs uppercase tracking-widest text-white">Out of Stock</span>
                        </div>
                      )}
                    </div>
                    <div className="text-[10px] uppercase tracking-widest text-slate-500 mb-1">SKU: {product.code}</div>
                    <h3 className="text-sm uppercase tracking-wider mb-2 text-slate-900">{product.name}</h3>
                    <div className="text-sm tracking-wider text-slate-900">₹{product.price.toLocaleString()}</div>
                  </motion.div>
                </Link>
              ))}
            </div>
          )}

          <div className="mt-12 sm:hidden text-center">
            <Link
              to="/products"
              className="inline-flex items-center gap-2 px-10 py-4 bg-slate-900 text-white hover:bg-slate-800 transition-colors uppercase tracking-wider text-sm"
            >
              Browse All Products <ArrowRight className="w-4 h-4" />
            </Link>
          </div>
        </div>
      </section>

      {/* Why Choose Us */}
      <section id="why-us" className="py-24 bg-white">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="mb-20">
            <h2 className="text-5xl md:text-7xl text-black tracking-tighter uppercase mb-4">WHY XPRESS GIFTING</h2>
            <p className="text-lg text-gray-600 uppercase tracking-wider">
              Your corporate gifting partner
            </p>
          </div>

          <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-px bg-black">
            {whyChooseUs.map((item, index) => (
              <motion.div
                key={index}
                className="bg-white p-10 hover:bg-gray-50 transition-colors group"
                initial={{ opacity: 0, y: 20 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true }}
                transition={{ delay: index * 0.05 }}
              >
                <item.icon className="w-8 h-8 mb-6 group-hover:scale-110 transition-transform" />
                <h3 className="text-xl uppercase tracking-wide mb-3 text-black">{item.title}</h3>
                <p className="text-sm text-gray-600 uppercase tracking-wider leading-relaxed">{item.desc}</p>
              </motion.div>
            ))}
          </div>
        </div>
      </section>

      {/* Contact / Lead Capture Section */}
      <section id="contact" className="py-24 bg-white">
        <div className="max-w-5xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="mb-16">
            <h2 className="text-5xl md:text-7xl text-black tracking-tighter uppercase mb-4">GET A QUOTE</h2>
            <p className="text-lg text-gray-600 uppercase tracking-wider">
              We&apos;ll respond within 24 hours
            </p>
          </div>

          <form className="border border-black/20 p-8 md:p-12">
            <div className="grid md:grid-cols-2 gap-6 mb-6">
              <div>
                <label className="block mb-3 text-xs uppercase tracking-widest text-black">Your Name *</label>
                <input
                  type="text"
                  className="w-full px-0 py-3 border-0 border-b border-black/20 bg-transparent text-black placeholder-gray-400 focus:outline-none focus:border-black transition-colors"
                  placeholder="JOHN DOE"
                  required
                />
              </div>
              <div>
                <label className="block mb-3 text-xs uppercase tracking-widest text-black">Company Name *</label>
                <input
                  type="text"
                  className="w-full px-0 py-3 border-0 border-b border-black/20 bg-transparent text-black placeholder-gray-400 focus:outline-none focus:border-black transition-colors"
                  placeholder="ABC CORPORATION"
                  required
                />
              </div>
            </div>

            <div className="grid md:grid-cols-2 gap-6 mb-6">
              <div>
                <label className="block mb-3 text-xs uppercase tracking-widest text-black">Email Address *</label>
                <input
                  type="email"
                  className="w-full px-0 py-3 border-0 border-b border-black/20 bg-transparent text-black placeholder-gray-400 focus:outline-none focus:border-black transition-colors"
                  placeholder="JOHN@COMPANY.COM"
                  required
                />
              </div>
              <div>
                <label className="block mb-3 text-xs uppercase tracking-widest text-black">Phone Number *</label>
                <input
                  type="tel"
                  className="w-full px-0 py-3 border-0 border-b border-black/20 bg-transparent text-black placeholder-gray-400 focus:outline-none focus:border-black transition-colors"
                  placeholder="+91 98765 43210"
                  required
                />
              </div>
            </div>

            <div className="grid md:grid-cols-2 gap-6 mb-6">
              <div>
                <label className="block mb-3 text-xs uppercase tracking-widest text-black">Quantity Required *</label>
                <select className="w-full px-0 py-3 border-0 border-b border-black/20 bg-transparent text-black focus:outline-none focus:border-black transition-colors">
                  <option className="bg-white" value="">SELECT QUANTITY RANGE</option>
                  <option className="bg-white" value="50-100">50-100 UNITS</option>
                  <option className="bg-white" value="100-500">100-500 UNITS</option>
                  <option className="bg-white" value="500-1000">500-1000 UNITS</option>
                  <option className="bg-white" value="1000+">1000+ UNITS</option>
                </select>
              </div>
              <div>
                <label className="block mb-3 text-xs uppercase tracking-widest text-black">Product Interest *</label>
                <select className="w-full px-0 py-3 border-0 border-b border-black/20 bg-transparent text-black focus:outline-none focus:border-black transition-colors">
                  <option className="bg-white" value="">SELECT CATEGORY</option>
                  {productCategories.map((cat) => (
                    <option key={cat.name} className="bg-white" value={cat.name}>
                      {cat.name.toUpperCase()}
                    </option>
                  ))}
                </select>
              </div>
            </div>

            <div className="mb-8">
              <label className="block mb-3 text-xs uppercase tracking-widest text-black">Additional Requirements</label>
              <textarea
                className="w-full px-0 py-3 border-0 border-b border-black/20 bg-transparent text-black placeholder-gray-400 focus:outline-none focus:border-black transition-colors resize-none"
                rows={3}
                placeholder="TELL US ABOUT YOUR REQUIREMENTS..."
              ></textarea>
            </div>

            <button
              type="submit"
              className="w-full px-8 py-5 bg-black text-white hover:bg-gray-800 transition-colors text-sm uppercase tracking-widest flex items-center justify-center gap-2 group"
            >
              Submit Request
              <ArrowRight className="w-4 h-4 group-hover:translate-x-1 transition-transform" />
            </button>
          </form>
        </div>
      </section>
    </>
  );
}
