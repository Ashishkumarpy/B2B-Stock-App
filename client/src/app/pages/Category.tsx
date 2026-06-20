import { useMemo, useState, useEffect } from 'react';
import { motion } from 'motion/react';
import { Link, useParams } from 'react-router';
import { ArrowRight, Filter, Loader2 } from 'lucide-react';
import { getProductsByCategory, type Product } from '../../lib/productService';
import { categorySlugToName } from '../../lib/category';
import { ProductCard } from '../components/ProductCard';

export default function Category() {
  const { slug } = useParams();
  const rawSlug = slug ? decodeURIComponent(slug) : '';
  const categoryName = rawSlug ? categorySlugToName(rawSlug) : '';

  const [products, setProducts] = useState<Product[]>([]);
  const [loading, setLoading] = useState(true);
  const [filterOpen, setFilterOpen] = useState(false);
  const [stockFilter, setStockFilter] = useState<'all' | 'in_stock' | 'out_of_stock'>('in_stock');
  const [sortBy, setSortBy] = useState<'newest' | 'price_asc' | 'price_desc'>('newest');

  useEffect(() => {
    if (!categoryName) return;
    setLoading(true);
    getProductsByCategory(categoryName).then((data) => {
      setProducts(data);
      setLoading(false);
    });
  }, [categoryName]);

  const visibleProducts = useMemo(() => {
    let result = products;

    if (stockFilter === 'in_stock') {
      result = result.filter((p) => p.stockStatus === 'in_stock' || p.stockStatus === 'low_stock');
    } else if (stockFilter === 'out_of_stock') {
      result = result.filter((p) => p.stockStatus === 'out_of_stock');
    }

    result = [...result].sort((a, b) => {
      if (sortBy === 'price_asc') return a.price - b.price;
      if (sortBy === 'price_desc') return b.price - a.price;
      return (b.createdAt ?? '').localeCompare(a.createdAt ?? '');
    });

    return result;
  }, [products, sortBy, stockFilter]);

  if (!categoryName) {
    return (
      <div className="min-h-screen bg-white text-slate-900 pt-36 flex items-center justify-center">
        <div className="text-center">
          <h1 className="text-5xl tracking-tighter uppercase mb-4">Category Not Found</h1>
          <Link to="/products" className="text-slate-600 hover:text-slate-900 uppercase tracking-wider text-sm">
            Back to Products
          </Link>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-white text-slate-900 pt-36">
      {/* Hero Section */}
      <section className="py-16 border-b border-slate-200">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.8 }}>
            <Link to="/products" className="text-sm text-slate-600 hover:text-slate-900 uppercase tracking-wider mb-6 inline-block">
              ← Back to All Products
            </Link>
            <h1 className="text-6xl md:text-8xl tracking-tighter uppercase mb-6">{categoryName}</h1>
            <p className="text-lg text-slate-600 uppercase tracking-wider max-w-2xl">
              Browse all {categoryName} products — custom branding available
            </p>
          </motion.div>
        </div>
      </section>

      {/* Filters */}
      <section className="py-6 border-b border-slate-200">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between">
            <div className="text-sm uppercase tracking-wider text-slate-600">
              {loading ? 'Loading…' : `${visibleProducts.length} Products`}
            </div>
            <button
              onClick={() => setFilterOpen((v) => !v)}
              className="flex items-center gap-2 px-6 py-3 border border-slate-200 hover:bg-slate-50 transition-colors text-sm uppercase tracking-wider"
            >
              <Filter className="w-4 h-4" /> Filter
            </button>
          </div>

          {filterOpen && (
            <div className="mt-6 grid grid-cols-1 md:grid-cols-2 gap-4 border border-slate-200 bg-slate-50 p-4">
              <div>
                <label className="block text-xs uppercase tracking-widest text-slate-600 mb-2">Stock</label>
                <select
                  value={stockFilter}
                  onChange={(e) => setStockFilter(e.target.value as typeof stockFilter)}
                  className="w-full bg-white border border-slate-200 px-4 py-3 text-sm uppercase tracking-wider text-slate-900 focus:outline-none focus:border-slate-900 transition-colors"
                >
                  <option value="all">All</option>
                  <option value="in_stock">In Stock</option>
                  <option value="out_of_stock">Out of Stock</option>
                </select>
              </div>

              <div>
                <label className="block text-xs uppercase tracking-widest text-slate-600 mb-2">Sort</label>
                <select
                  value={sortBy}
                  onChange={(e) => setSortBy(e.target.value as typeof sortBy)}
                  className="w-full bg-white border border-slate-200 px-4 py-3 text-sm uppercase tracking-wider text-slate-900 focus:outline-none focus:border-slate-900 transition-colors"
                >
                  <option value="newest">Newest</option>
                  <option value="price_asc">Price: Low to High</option>
                  <option value="price_desc">Price: High to Low</option>
                </select>
              </div>
            </div>
          )}
        </div>
      </section>

      {/* Products Grid */}
      <section className="py-16">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          {loading ? (
            <div className="flex items-center justify-center py-32">
              <Loader2 className="w-8 h-8 animate-spin text-slate-500" />
            </div>
          ) : visibleProducts.length === 0 ? (
            <div className="text-center py-32">
              <p className="text-slate-500 uppercase tracking-widest text-sm mb-4">No products in this category yet.</p>
              <Link to="/products" className="text-slate-900 underline text-xs uppercase tracking-widest">Browse All Products</Link>
            </div>
          ) : (
            <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-6">
              {visibleProducts.map((product, index) => (
                <ProductCard key={product.id} product={product} index={index} />
              ))}
            </div>
          )}
        </div>
      </section>

      {/* CTA Section */}
      <section className="py-24 bg-slate-900 text-white">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
          <h2 className="text-4xl md:text-5xl tracking-tighter uppercase mb-6">NEED BULK ORDERS?</h2>
          <p className="text-lg text-white/80 uppercase tracking-wider mb-10">Get special pricing for orders above 100 units</p>
          <Link
            to="/#contact"
            className="inline-flex items-center gap-2 px-12 py-4 bg-white text-slate-900 hover:bg-slate-100 transition-colors uppercase tracking-wider text-sm"
          >
            Request Quote <ArrowRight className="w-4 h-4" />
          </Link>
        </div>
      </section>
    </div>
  );
}
